output "open_shift_api_int_lb_addr" {
  value = oci_load_balancer_load_balancer.openshift_api_int_lb.ip_address_details[0].ip_address
}

output "open_shift_api_apps_lb_addr" {
  value = oci_load_balancer_load_balancer.openshift_api_apps_lb.ip_address_details[0].ip_address
}

output "oci_ccm_config" {
  value = <<OCICCMCONFIG
useInstancePrincipals: true
compartment: ${var.compartment_ocid}
vcn: ${oci_core_vcn.openshift_vcn.id}
loadBalancer:
  subnet1: ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}
  securityListManagementMode: Frontend
  securityLists:
    ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}: ${var.enable_private_dns ? oci_core_security_list.private.id : oci_core_security_list.public.id}
rateLimiter:
  rateLimitQPSRead: 20.0
  rateLimitBucketRead: 5
  rateLimitQPSWrite: 20.0
  rateLimitBucketWrite: 5
  OCICCMCONFIG
}

output "one_big_manifest" {
  value = <<EOT
---
# oci-ccm.yml
# oci-ccm-00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: oci-cloud-controller-manager
  annotations:
    workload.openshift.io/allowed: management
  labels:
    "pod-security.kubernetes.io/enforce": "privileged"
    "pod-security.kubernetes.io/audit": "privileged"
    "pod-security.kubernetes.io/warn": "privileged"
    "security.openshift.io/scc.podSecurityLabelSync": "false"
    "openshift.io/run-level": "0"
    "pod-security.kubernetes.io/enforce-version": "v1.24"
---
# oci-ccm-04-cloud-controller-manager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  creationTimestamp: null
  name: oci-cloud-controller-manager
  namespace: oci-cloud-controller-manager
stringData:
  cloud-provider.yaml: |
    useInstancePrincipals: true
    compartment: ${var.compartment_ocid}
    vcn: ${oci_core_vcn.openshift_vcn.id}
    loadBalancer:
      subnet1: ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}
      securityListManagementMode: Frontend
      securityLists:
        ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}: ${var.enable_private_dns ? oci_core_security_list.private.id : oci_core_security_list.public.id}
    rateLimiter:
      rateLimitQPSRead: 20.0
      rateLimitBucketRead: 5
      rateLimitQPSWrite: 20.0
      rateLimitBucketWrite: 5
---
# oci-ccm-01-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: oci-cloud-controller-manager
---
# oci-ccm-02-cluster-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:cloud-controller-manager
  labels:
    kubernetes.io/cluster-service: "true"
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - '*'
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - list
  - watch
  - patch
  - get
- apiGroups:
  - ""
  resources:
  - services/status
  verbs:
  - patch
  - get
  - update
- apiGroups:
    - ""
  resources:
    - configmaps
  resourceNames:
    - "extension-apiserver-authentication"
  verbs:
    - get
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - list
  - watch
  - create
  - patch
  - update
# For leader election
- apiGroups:
  - ""
  resources:
  - endpoints
  verbs:
  - create
- apiGroups:
  - ""
  resources:
  - endpoints
  resourceNames:
  - "cloud-controller-manager"
  verbs:
  - get
  - list
  - watch
  - update
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - create
- apiGroups:
    - "coordination.k8s.io"
  resources:
    - leases
  verbs:
    - get
    - create
    - update
    - delete
    - patch
    - watch
- apiGroups:
  - ""
  resources:
  - configmaps
  resourceNames:
  - "cloud-controller-manager"
  verbs:
  - get
  - update
- apiGroups:
    - ""
  resources:
    - configmaps
  resourceNames:
    - "extension-apiserver-authentication"
  verbs:
    - get
    - list
    - watch
- apiGroups:
  - ""
  resources:
  - serviceaccounts
  verbs:
  - create
  - list
  - get
  - watch
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
# For the PVL
- apiGroups:
  - ""
  resources:
  - persistentvolumes
  verbs:
  - list
  - watch
  - patch
---
# oci-ccm-03-cluster-role-binding.yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oci-cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:cloud-controller-manager
subjects:
- kind: ServiceAccount
  name: cloud-controller-manager
  namespace: oci-cloud-controller-manager
---
# oci-ccm-05-daemon-set.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: oci-cloud-controller-manager
  namespace: oci-cloud-controller-manager
  labels:
    k8s-app: oci-cloud-controller-manager
spec:
  selector:
    matchLabels:
      component: oci-cloud-controller-manager
      tier: control-plane
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        component: oci-cloud-controller-manager
        tier: control-plane
    spec:
      serviceAccountName: cloud-controller-manager
      hostNetwork: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      priorityClassName: system-cluster-critical
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoSchedule
      volumes:
        - name: cfg
          secret:
            secretName: oci-cloud-controller-manager
        - name: kubernetes
          hostPath:
            path: /etc/kubernetes
      containers:
        - name: oci-cloud-controller-manager
          image: phx.ocir.io/axkcy3juscqn/openshift-ccm-csi:beta-v1
          command:
            - /bin/bash
            - -c
            - |
              #!/bin/bash
              set -o allexport
              if [[ -f /etc/kubernetes/apiserver-url.env ]]; then
                source /etc/kubernetes/apiserver-url.env
              fi
              exec /usr/local/bin/oci-cloud-controller-manager --cloud-config=/etc/oci/cloud-provider.yaml --cloud-provider=oci --leader-elect-resource-lock=leases --concurrent-service-syncs=3 --v=2
          volumeMounts:
            - name: cfg
              mountPath: /etc/oci
              readOnly: true
            - name: kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
---

# oci-csi.yml
# oci-csi-00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: oci-csi
  annotations:
    workload.openshift.io/allowed: management
  labels:
    "pod-security.kubernetes.io/enforce": "privileged"
    "pod-security.kubernetes.io/audit": "privileged"
    "pod-security.kubernetes.io/warn": "privileged"
    "security.openshift.io/scc.podSecurityLabelSync": "false"
    "openshift.io/run-level": "0"
    "pod-security.kubernetes.io/enforce-version": "v1.24"
---
# oci-csi-01-config.yaml
apiVersion: v1
kind: Secret
metadata:
  creationTimestamp: null
  name: oci-volume-provisioner
  namespace: oci-csi
stringData:
  config.yaml: |
    useInstancePrincipals: true
    compartment: ${var.compartment_ocid}
    vcn: ${oci_core_vcn.openshift_vcn.id}
    loadBalancer:
      subnet1: ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}
      securityListManagementMode: Frontend
      securityLists:
        ${var.enable_private_dns && !local.is_control_plane_iscsi_type && !local.is_compute_iscsi_type ? oci_core_subnet.private.id : var.enable_private_dns ? oci_core_subnet.private2[0].id : oci_core_subnet.public.id}: ${var.enable_private_dns ? oci_core_security_list.private.id : oci_core_security_list.public.id}
    rateLimiter:
      rateLimitQPSRead: 20.0
      rateLimitBucketRead: 5
      rateLimitQPSWrite: 20.0
      rateLimitBucketWrite: 5
---
# oci-csi-02-controller-driver.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    deprecated.daemonset.template.generation: "1"
  generation: 1
  name: csi-oci-controller
  namespace: oci-csi
spec:
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: csi-oci-controller
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: csi-oci-controller
        role: csi-oci
    spec:
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      containers:
        - name: csi-volume-provisioner
          image: registry.k8s.io/sig-storage/csi-provisioner:v3.6.0
          args:
            - --csi-address=/var/run/shared-tmpfs/csi.sock
            - --volume-name-prefix=csi
            - --feature-gates=Topology=true
            - --timeout=120s
            - --leader-election
            - --leader-election-namespace=oci-csi
          volumeMounts:
            - name: config
              mountPath: /etc/oci/
              readOnly: true
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: csi-fss-volume-provisioner
          image: registry.k8s.io/sig-storage/csi-provisioner:v3.6.0
          args:
            - --csi-address=/var/run/shared-tmpfs/csi-fss.sock
            - --volume-name-prefix=csi-fss
            - --feature-gates=Topology=true
            - --timeout=120s
            - --leader-election
            - --leader-election-namespace=oci-csi
          volumeMounts:
            - name: config
              mountPath: /etc/oci/
              readOnly: true
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: csi-attacher
          image: registry.k8s.io/sig-storage/csi-attacher:v4.4.0
          args:
            - --csi-address=/var/run/shared-tmpfs/csi.sock
            - --timeout=120s
            - --leader-election=true
            - --leader-election-namespace=oci-csi
          volumeMounts:
            - name: config
              mountPath: /etc/oci/
              readOnly: true
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: csi-resizer
          image: registry.k8s.io/sig-storage/csi-resizer:v1.9.0
          args:
            - --csi-address=/var/run/shared-tmpfs/csi.sock
            - --leader-election
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: snapshot-controller
          image: registry.k8s.io/sig-storage/snapshot-controller:v6.2.0
          args:
            - --leader-election
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: csi-snapshotter
          image: registry.k8s.io/sig-storage/csi-snapshotter:v6.2.0
          args:
            - --csi-address=/var/run/shared-tmpfs/csi.sock
            - --leader-election
          imagePullPolicy: "IfNotPresent"
          volumeMounts:
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
        - name: oci-csi-controller-driver
          args:
            - --endpoint=unix://var/run/shared-tmpfs/csi.sock
            - --fss-csi-endpoint=unix://var/run/shared-tmpfs/csi-fss.sock
          command:
            - /usr/local/bin/oci-csi-controller-driver
          image: phx.ocir.io/axkcy3juscqn/openshift-ccm-csi:beta-v1
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: config
              mountPath: /etc/oci/
              readOnly: true
            - name: kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
            - mountPath: /var/run/shared-tmpfs
              name: shared-tmpfs
      volumes:
        - name: config
          secret:
            secretName: oci-volume-provisioner
        - name: kubernetes
          hostPath:
            path: /etc/kubernetes
        - name: shared-tmpfs
          emptyDir: {}
      dnsPolicy: ClusterFirst
      hostNetwork: true
      imagePullSecrets:
        - name: image-pull-secret
      restartPolicy: Always
      schedulerName: default-scheduler
      serviceAccount: csi-oci-node-sa
      serviceAccountName: csi-oci-node-sa
      terminationGracePeriodSeconds: 30
      tolerations:
        - operator: Exists
---
# oci-csi-03-fss-driver.yaml
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: fss.csi.oraclecloud.com
spec:
  attachRequired: false
  podInfoOnMount: false

---
# oci-csi-04-bv-driver.yaml
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: blockvolume.csi.oraclecloud.com
spec:
  fsGroupPolicy: File
---
# oci-csi-05-iscsiadm.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: oci-csi-iscsiadm
  namespace: oci-csi
data:
  iscsiadm: |
    #!/bin/sh
    if [ -x /host/sbin/iscsiadm ]; then
      chroot /host /sbin/iscsiadm "$@"
    elif [ -x /host/usr/local/sbin/iscsiadm ]; then
      chroot /host /usr/local/sbin/iscsiadm "$@"
    elif [ -x /host/bin/iscsiadm ]; then
      chroot /host /bin/iscsiadm "$@"
    elif [ -x /host/usr/local/bin/iscsiadm ]; then
      chroot /host /usr/local/bin/iscsiadm "$@"
    else
      chroot /host iscsiadm "$@"
    fi
---
# oci-csi-06-fss-csi.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oci-fss-csi
  namespace: oci-csi
data:
  mount: |-
    #!/bin/sh
    if [ -x /sbin/mount ]; then
    chroot /host mount "$@"
    elif [ -x /usr/local/sbin/mount ]; then
    chroot /host mount "$@"
    elif [ -x /usr/sbin/mount ]; then
    chroot /host mount "$@"
    elif [ -x /usr/local/bin/mount ]; then
    chroot /host mount "$@"
    else
    chroot /host mount "$@"
    fi
  umount: |-
    #!/bin/sh
    if [ -x /sbin/umount ]; then
    chroot /host umount "$@"
    elif [ -x /usr/local/sbin/umount ]; then
    chroot /host umount "$@"
    elif [ -x /usr/sbin/umount ]; then
    chroot /host umount "$@"
    elif [ -x /usr/local/bin/umount ]; then
    chroot /host umount "$@"
    else
    chroot /host umount "$@"
    fi
  umount.oci-fss: |-
    #!/bin/sh
    if [ -x /sbin/umount-oci-fss ]; then
    chroot /host umount.oci-fss "$@"
    elif [ -x /usr/local/sbin/umount-oci-fss ]; then
    chroot /host umount.oci-fss "$@"
    elif [ -x /usr/sbin/umount-oci-fss ]; then
    chroot /host umount.oci-fss "$@"
    elif [ -x /usr/local/bin/umount-oci-fss ]; then
    chroot /host umount.oci-fss "$@"
    else
    chroot /host umount.oci-fss "$@"
    fi
---
# oci-csi-07-node-driver.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  annotations:
    deprecated.daemonset.template.generation: "1"
  generation: 1
  name: csi-oci-node
  namespace: oci-csi
spec:
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: csi-oci-node
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: csi-oci-node
        role: csi-oci
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
      containers:
        - name: oci-csi-node-driver
          args:
            - --v=2
            - --endpoint=unix:///csi/csi.sock
            - --nodeid=$(KUBE_NODE_NAME)
            - --loglevel=debug
            - --fss-endpoint=unix:///fss/csi.sock
          command:
            - /usr/local/bin/oci-csi-node-driver
          env:
            - name: KUBE_NODE_NAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: spec.nodeName
            - name: PATH
              value: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/host/usr/bin:/host/sbin
          image: phx.ocir.io/axkcy3juscqn/openshift-ccm-csi:beta-v1
          securityContext:
            privileged: true
          volumeMounts:
            - mountPath: /csi
              name: plugin-dir
            - mountPath: /fss
              name: fss-plugin-dir
            - mountPath: /var/lib/kubelet
              mountPropagation: Bidirectional
              name: pods-mount-dir
            - mountPath: /dev
              name: device-dir
            - mountPath: /host
              mountPropagation: HostToContainer
              name: host-root
            - mountPath: /sbin/iscsiadm
              name: chroot-iscsiadm
              subPath: iscsiadm
            - mountPath: /host/var/lib/kubelet
              mountPropagation: Bidirectional
              name: encrypt-pods-mount-dir
            - mountPath: /sbin/umount.oci-fss
              name: fss-driver-mounts
              subPath: umount.oci-fss
            - mountPath: /sbin/umount
              name: fss-driver-mounts
              subPath: umount
            - mountPath: /sbin/mount
              name: fss-driver-mounts
              subPath: mount
        - name: csi-node-registrar
          args:
            - --csi-address=/csi/csi.sock
            - --kubelet-registration-path=/var/lib/kubelet/plugins/blockvolume.csi.oraclecloud.com/csi.sock
          image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.5.1
          securityContext:
            privileged: true
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - rm -rf /registration/blockvolume.csi.oraclecloud.com /registration/blockvolume.csi.oraclecloud.com-reg.sock
          volumeMounts:
            - mountPath: /csi
              name: plugin-dir
            - mountPath: /registration
              name: registration-dir
        - name: csi-node-registrar-fss
          args:
            - --csi-address=/fss/csi.sock
            - --kubelet-registration-path=/var/lib/kubelet/plugins/fss.csi.oraclecloud.com/csi.sock
          image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.5.0
          securityContext:
            privileged: true
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - rm -rf /registration/fss.csi.oraclecloud.com /registration/fss.csi.oraclecloud.com-reg.sock
          volumeMounts:
            - mountPath: /fss
              name: fss-plugin-dir
            - mountPath: /registration
              name: registration-dir
      dnsPolicy: ClusterFirst
      hostNetwork: true
      restartPolicy: Always
      schedulerName: default-scheduler
      serviceAccount: csi-oci-node-sa
      serviceAccountName: csi-oci-node-sa
      terminationGracePeriodSeconds: 30
      tolerations:
        - operator: Exists
      volumes:
        - hostPath:
            path: /var/lib/kubelet/plugins_registry/
            type: DirectoryOrCreate
          name: registration-dir
        - hostPath:
            path: /var/lib/kubelet/plugins/blockvolume.csi.oraclecloud.com
            type: DirectoryOrCreate
          name: plugin-dir
        - hostPath:
            path: /var/lib/kubelet/plugins/fss.csi.oraclecloud.com
            type: DirectoryOrCreate
          name: fss-plugin-dir
        - hostPath:
            path: /var/lib/kubelet
            type: Directory
          name: pods-mount-dir
        - hostPath:
            path: /var/lib/kubelet
            type: Directory
          name: encrypt-pods-mount-dir
        - hostPath:
            path: /dev
            type: ""
          name: device-dir
        - hostPath:
            path: /
            type: Directory
          name: host-root
        - configMap:
            name: oci-csi-iscsiadm
            defaultMode: 0755
          name: chroot-iscsiadm
        - configMap:
            name: oci-fss-csi
            defaultMode: 0755
          name: fss-driver-mounts
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
---
# oci-csi-08-node-rbac-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
 name: csi-oci-node-sa
 namespace: oci-csi
---
# oci-csi-09-node-rbac-cr.yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: csi-oci
 namespace: oci-csi
rules:
 - apiGroups: [""]
   resources: ["events"]
   verbs: ["get", "list", "watch", "create", "update", "patch"]
 - apiGroups: [""]
   resources: ["nodes"]
   verbs: ["get", "list", "watch"]
 - apiGroups: ["volume.oci.oracle.com"]
   resources: ["blockscsiinfos"]
   verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
 - apiGroups: [""]
   resources: ["persistentvolumes"]
   verbs: ["get", "list", "watch", "create", "delete", "patch"]
 - apiGroups: [""]
   resources: ["persistentvolumeclaims"]
   verbs: ["get", "list", "watch", "update", "create"]
 - apiGroups: ["storage.k8s.io"]
   resources: ["storageclasses", "volumeattachments", "volumeattachments/status", "csinodes"]
   verbs: ["get", "list", "watch", "patch"]
 - apiGroups: ["coordination.k8s.io"]
   resources: ["leases"]
   verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
 - apiGroups: [""]
   resources: ["endpoints"]
   verbs: ["get", "watch", "create", "update"]
 - apiGroups: [""]
   resources: ["pods"]
   verbs: ["get", "list", "watch"]
 - apiGroups: [""]
   resources: ["persistentvolumeclaims/status"]
   verbs: ["patch"]
 - apiGroups: [ "snapshot.storage.k8s.io" ]
   resources: [ "volumesnapshotclasses" ]
   verbs: [ "get", "list", "watch" ]
 - apiGroups: [ "snapshot.storage.k8s.io" ]
   resources: [ "volumesnapshotcontents" ]
   verbs: [ "create", "get", "list", "watch", "update", "delete", "patch" ]
 - apiGroups: [ "snapshot.storage.k8s.io" ]
   resources: [ "volumesnapshotcontents/status" ]
   verbs: [ "update", "patch" ]
 - apiGroups: [ "snapshot.storage.k8s.io" ]
   resources: [ "volumesnapshots" ]
   verbs: [ "get", "list", "watch", "update", "patch" ]
 - apiGroups: [ "snapshot.storage.k8s.io" ]
   resources: [ "volumesnapshots/status" ]
   verbs: [ "update", "patch" ]
---
# oci-csi-10-node-rbac-crb.yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: csi-oci-binding
subjects:
 - kind: ServiceAccount
   name: csi-oci-node-sa
   namespace: oci-csi
roleRef:
 kind: ClusterRole
 name: csi-oci
 apiGroup: rbac.authorization.k8s.io
---
# oci-csi-11-storage-class-bv.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: oci-bv
provisioner: blockvolume.csi.oraclecloud.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
---
# oci-csi-12-storage-class-bv-enc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: oci-bv-encrypted
provisioner: blockvolume.csi.oraclecloud.com
parameters:
  attachment-type: "paravirtualized"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---

# cluster-network-03-config.yml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      gatewayConfig:
        ipv4:
          internalMasqueradeSubnet: 169.254.64.0/18
    type: OVNKubernetes
  managementState: Managed
---

# machineconfig-ccm.yml
# 99_openshift-machineconfig_00-master-kubelet-providerid.yaml
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 00-master-oci-kubelet-providerid
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/1yPUYvaQBCA3/dXTFMf2odkrbSFWlNQE2moJEW9exGRdTO5DBd3w+4YvBP/+yF6IPf0zcPMxzefP8kdGblTvhYeGUKE0EJLLVaKGiHyIkmnRT6LJbKW/sUz7ssb5fNhhw1y5NF1pDEq5aAfWk1h62xHJToqI21NJQRVsL64g97p3XgOYPMbuEYjAABQ1xaC3DI4bBulyTwBHsnzZbi/um4fiaEvKhJZvlyN82m6zZK490UfXAPhXwjGB66to1fFZM0QJqgcOiic0g0GEPo51MztUMpvP39Fgx/foxulbbXsBpKMZ2U0Siq/CqEVw58P8aNRWszEenn9fSNS05GzZo+G4+DfwySdp6vt/0XxmCXpIktiq2koZe90F3wOxMXxFgAA///yWfIkhAEAAA==
          mode: 493
          path: /usr/local/bin/oci-kubelet-providerid
    systemd:
      units:
        - contents: |
            [Unit]
            Description=Fetch kubelet provider id from OCI Metadata

            # Wait for NetworkManager to report it's online
            After=NetworkManager-wait-online.service
            # Run before kubelet
            Before=kubelet.service

            [Service]
            ExecStart=/usr/local/bin/oci-kubelet-providerid
            Type=oneshot

            [Install]
            WantedBy=network-online.target
          enabled: true
          name: oci-kubelet-providerid.service
---
# 99_openshift-machineconfig_00-worker-kubelet-providerid.yaml
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 00-worker-oci-kubelet-providerid
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/1yPUYvaQBCA3/dXTFMf2odkrbSFWlNQE2moJEW9exGRdTO5DBd3w+4YvBP/+yF6IPf0zcPMxzefP8kdGblTvhYeGUKE0EJLLVaKGiHyIkmnRT6LJbKW/sUz7ssb5fNhhw1y5NF1pDEq5aAfWk1h62xHJToqI21NJQRVsL64g97p3XgOYPMbuEYjAABQ1xaC3DI4bBulyTwBHsnzZbi/um4fiaEvKhJZvlyN82m6zZK490UfXAPhXwjGB66to1fFZM0QJqgcOiic0g0GEPo51MztUMpvP39Fgx/foxulbbXsBpKMZ2U0Siq/CqEVw58P8aNRWszEenn9fSNS05GzZo+G4+DfwySdp6vt/0XxmCXpIktiq2koZe90F3wOxMXxFgAA///yWfIkhAEAAA==
          mode: 493
          path: /usr/local/bin/oci-kubelet-providerid
    systemd:
      units:
        - contents: |
            [Unit]
            Description=Fetch kubelet provider id from OCI Metadata

            # Wait for NetworkManager to report it's online
            After=NetworkManager-wait-online.service
            # Run before kubelet
            Before=kubelet.service

            [Service]
            ExecStart=/usr/local/bin/oci-kubelet-providerid
            Type=oneshot

            [Install]
            WantedBy=network-online.target
          enabled: true
          name: oci-kubelet-providerid.service
---

# machineconfig-consistent-device-path.yml
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 00-worker-oci-add-consistent-device-path
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/6SQQW/TQBCF7/4VT7Z6gRBLcPahNBZYTVwrTo1yQuvdMV1h70S741UR4r8juzlwqZDgNpr93ns7L8ODV3ok3I08G1Ru8CqIn7XMnrZoRlKBYBiOBZ4mjpQkGb4Q5kDYlV1ze/oM5Qyq3dd1jspb1Y8UIAxDQn6yjiBPhP1jnWFgD9vetVXedOhVILPK67baQYn4Fai7A708JhlOTwTNLpIPlh0Gz9OL1QIuMmEM3pIz4w8YilYTnJoINiDY6TLSu6vLwH5SsuxzQzHn9XTW9jpF8/ycZHiPnjRP9CrVb/Dhb4xerwoMdttres8siDzOi0x5wsVztIbMWs6fH+fhNVu1TZL78liX+6JIg3mTbtA+fmzP7ak8FEXaj6y/pxuUdfdzV3anc1P+KorU2LBsm+PDp+PtoUhzEp2ztrOheFlqDUJOnJqs+4abBW3Ph31V378t0hud/kPiRXmxYtn9T+zvAAAA//+dZsHsnQIAAA==
          mode: 511
          path: /etc/udev/rules.d/99-systemoci-persistent-names.rules
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/6xW627bOhL+r6eYSu7aTqNrmhT1bgokbYo1kKbdTdIukGQXNDWyiVCkSlLOpdvz7Ack5VuS9lxwgkCWyOHMNzPfDCd6lk6YSCdEz4IgglOqWGPASKAKiUHQdzVn4loDE1DinFHUYGbEANMwIRpLkAKOz09g/E4nQQTHTFzDvCRA+A2509BIJoy2Cs0MQUlpOjVW+GzGNGhv8kaqaw1S8DuopAJ2+vZ0DMQYQmc1WhWDQzQEFHIkGp3Mp9MPQwt6XIFo6wkqkBU0RJEaDSoNE2RiChqF8fZXxpgGIQ3g15Zwu5cHEWzDDYKZKXkDRAAqJVUCXxDwtkFqHPxrVAJ55wAIUiNwdo0Q6pKE2/ZnEgIamgSsggsIe1EIsUDI4ervVoEIAJDOJIRMzAlnJfzD63oTwpu/FXb3lhnIg4oFToXV8e7o86eDs3+GsA9b4Zwpw2S4BVcrjRGca+vo+N3/rKD1R6FRDOfoUB+fQ+TEFgJMg9cTN5TFWZZlI/v/MsliTTWLs1E2KkZ54Q59YWbm1Oh2og0zrWFSuFjdyJaXMEEgE47W6hQN5AXczBidWSPe+EmXnCQA+7XfG/gQ9Do4IfwfLI/6Ok22RmnaHwbINa451kXgCcdOOs8WEkxD2rE0bTgxlVR1OpPa7KYatWZS7KSGqCma3VE2ylL3HOVFOuGSXqe6pCufK6a0eeC1i4NRFtQEqaxRw9OHNVIpyt91ej3KTD11hhNtgM6IItSgsk4qrOUcSyCitJkgapWERYSc2s0MrDKTF4+ysaTZg2ysvi8HF+nV5TDZSi/z5brup0nPJW3BWbgNe8fnJ5av4W24zvwVtyNbWJQIaDWu87Zi01YhyNZ0DWBiG8Zc8rZGHWwwmDVxvvc6KXZfJllSjHaKvSxmjr7sq0iKLN+NsyKRilCOiVUzarFiMW9FbKv9oLKhfJLXlsZrsocfP565SH3rrKc+Mt+DaLn1mNIPGB094Y9Lm0Iqp4LdYwk3lgNrhhcNoLPiG8Bqf7MJdADyVf4iXV6Q+P5qyz0jHwlJWerf5iWJpv1FWrIuLWMB1LZXWcGnz3C4QuuZ+Ec6SDaycT68A9I0/M6S/ofRfkBToiGHIILc2tENUka4h6VQo7LEt+1/PZbLjrsWrDBfZ5//+/Nh6s6vB+sMtbtZUGjLWst6i5h0fgQK9/v/vcji11cven0L8JlPqMf3C/QUwtUVrCA+rBDCub2NoCa3rG7rjYvHSNt65+X9PcRApVKoGylKF2fpSvtVVsCg2IMX7rkFxd5wuAiTgxBPDYSvsuJnRVpK0TcdkGXP7Yxz1G4YEJBv6uUIYfZDrePKc+lfJ5Zm9pUJKmuLvHOwJobO0F8gUmAQQYNKM238uGGXK8ZR32mD9bbX7qqnIoy3CoP3Jwcfjn5+0/hesdHgXF0lW65gnT9xBWE6JyrlctrxIaZctmVMpihM2vB2yoROJWWxuwRIaySVomLTtOcwhI9ufjfzOJY0xPZ8afPbcsPcZzcbwek1axo3vfj5y49jTIrwYTTfSjFHZVa0syoPTt+Ox+7KCOhMDYbwLQBoFBOmgsvL3qB77T/PdmTf1cMw+N5p00a11ACBAjga2yV1W1XsFlq9KGI/79kJroAaidAwLyfbsLP8oO5m0hKksEKvlhuErHaS4Pjo7Ozo3/l+bzA4Pj9JHUH9WmHX7CLEMOjEOgrDc8/kJeX8gRBi/ArZWrwXmvr3vn435HMvnz/qEAtMfX+oG0U293oDOlNgUXfIXsDr3eFw6AQrtphfVq5siBdWfM+LP4Up+8sw7a1hsmw5PX//fvyf/aW9ZeyC4GFjDH+7Mfa8umgaBr4t/hoAAP//Hf+NU0wMAAA=
          mode: 511
          path: /etc/ociudevpersistentnaming
---
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 00-master-oci-add-consistent-device-path
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/6SQQW/TQBCF7/4VT7Z6gRBLcPahNBZYTVwrTo1yQuvdMV1h70S741UR4r8juzlwqZDgNpr93ns7L8ODV3ok3I08G1Ru8CqIn7XMnrZoRlKBYBiOBZ4mjpQkGb4Q5kDYlV1ze/oM5Qyq3dd1jspb1Y8UIAxDQn6yjiBPhP1jnWFgD9vetVXedOhVILPK67baQYn4Fai7A708JhlOTwTNLpIPlh0Gz9OL1QIuMmEM3pIz4w8YilYTnJoINiDY6TLSu6vLwH5SsuxzQzHn9XTW9jpF8/ycZHiPnjRP9CrVb/Dhb4xerwoMdttres8siDzOi0x5wsVztIbMWs6fH+fhNVu1TZL78liX+6JIg3mTbtA+fmzP7ak8FEXaj6y/pxuUdfdzV3anc1P+KorU2LBsm+PDp+PtoUhzEp2ztrOheFlqDUJOnJqs+4abBW3Ph31V378t0hud/kPiRXmxYtn9T+zvAAAA//+dZsHsnQIAAA==
          mode: 511
          path: /etc/udev/rules.d/99-systemoci-persistent-names.rules
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/6xW627bOhL+r6eYSu7aTqNrmhT1bgokbYo1kKbdTdIukGQXNDWyiVCkSlLOpdvz7Ack5VuS9lxwgkCWyOHMNzPfDCd6lk6YSCdEz4IgglOqWGPASKAKiUHQdzVn4loDE1DinFHUYGbEANMwIRpLkAKOz09g/E4nQQTHTFzDvCRA+A2509BIJoy2Cs0MQUlpOjVW+GzGNGhv8kaqaw1S8DuopAJ2+vZ0DMQYQmc1WhWDQzQEFHIkGp3Mp9MPQwt6XIFo6wkqkBU0RJEaDSoNE2RiChqF8fZXxpgGIQ3g15Zwu5cHEWzDDYKZKXkDRAAqJVUCXxDwtkFqHPxrVAJ55wAIUiNwdo0Q6pKE2/ZnEgIamgSsggsIe1EIsUDI4ervVoEIAJDOJIRMzAlnJfzD63oTwpu/FXb3lhnIg4oFToXV8e7o86eDs3+GsA9b4Zwpw2S4BVcrjRGca+vo+N3/rKD1R6FRDOfoUB+fQ+TEFgJMg9cTN5TFWZZlI/v/MsliTTWLs1E2KkZ54Q59YWbm1Oh2og0zrWFSuFjdyJaXMEEgE47W6hQN5AXczBidWSPe+EmXnCQA+7XfG/gQ9Do4IfwfLI/6Ok22RmnaHwbINa451kXgCcdOOs8WEkxD2rE0bTgxlVR1OpPa7KYatWZS7KSGqCma3VE2ylL3HOVFOuGSXqe6pCufK6a0eeC1i4NRFtQEqaxRw9OHNVIpyt91ej3KTD11hhNtgM6IItSgsk4qrOUcSyCitJkgapWERYSc2s0MrDKTF4+ysaTZg2ysvi8HF+nV5TDZSi/z5brup0nPJW3BWbgNe8fnJ5av4W24zvwVtyNbWJQIaDWu87Zi01YhyNZ0DWBiG8Zc8rZGHWwwmDVxvvc6KXZfJllSjHaKvSxmjr7sq0iKLN+NsyKRilCOiVUzarFiMW9FbKv9oLKhfJLXlsZrsocfP565SH3rrKc+Mt+DaLn1mNIPGB094Y9Lm0Iqp4LdYwk3lgNrhhcNoLPiG8Bqf7MJdADyVf4iXV6Q+P5qyz0jHwlJWerf5iWJpv1FWrIuLWMB1LZXWcGnz3C4QuuZ+Ec6SDaycT68A9I0/M6S/ofRfkBToiGHIILc2tENUka4h6VQo7LEt+1/PZbLjrsWrDBfZ5//+/Nh6s6vB+sMtbtZUGjLWst6i5h0fgQK9/v/vcji11cven0L8JlPqMf3C/QUwtUVrCA+rBDCub2NoCa3rG7rjYvHSNt65+X9PcRApVKoGylKF2fpSvtVVsCg2IMX7rkFxd5wuAiTgxBPDYSvsuJnRVpK0TcdkGXP7Yxz1G4YEJBv6uUIYfZDrePKc+lfJ5Zm9pUJKmuLvHOwJobO0F8gUmAQQYNKM238uGGXK8ZR32mD9bbX7qqnIoy3CoP3Jwcfjn5+0/hesdHgXF0lW65gnT9xBWE6JyrlctrxIaZctmVMpihM2vB2yoROJWWxuwRIaySVomLTtOcwhI9ufjfzOJY0xPZ8afPbcsPcZzcbwek1axo3vfj5y49jTIrwYTTfSjFHZVa0syoPTt+Ox+7KCOhMDYbwLQBoFBOmgsvL3qB77T/PdmTf1cMw+N5p00a11ACBAjga2yV1W1XsFlq9KGI/79kJroAaidAwLyfbsLP8oO5m0hKksEKvlhuErHaS4Pjo7Ozo3/l+bzA4Pj9JHUH9WmHX7CLEMOjEOgrDc8/kJeX8gRBi/ArZWrwXmvr3vn435HMvnz/qEAtMfX+oG0U293oDOlNgUXfIXsDr3eFw6AQrtphfVq5siBdWfM+LP4Up+8sw7a1hsmw5PX//fvyf/aW9ZeyC4GFjDH+7Mfa8umgaBr4t/hoAAP//Hf+NU0wMAAA=
          mode: 511
          path: /etc/ociudevpersistentnaming
---

# machineconfig-csi.yml
# 99_openshift-machineconfig_00-master-iscsi-service.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-iscsid
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - enabled: true
        name: iscsid.service
---
# 99_openshift-machineconfig_00-worker-iscsi-service.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-iscsid
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - enabled: true
        name: iscsid.service
---

# oci-eval-user-data.yml
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 00-master-oci-eval-user-data
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/3SRQY/aMBCF7/4VD5cDHIyBBqSicGgPqIeK/gQ0SSaNpcROHSeCtvz3KrBhw2r3lEjjed97bz5NdNt4nRir2XZIqCmEaDhAcXt2qE3NOZlSCJNjgrZhf8oo0CnZRvvpLG19CfUd8msbCufNHwrG2R2+MXn2+OkpLVlCqYrOKpiK8XkJpTwHf8Fm+FMZl3QZjVTqrPWctw1nUD9QhFDvtF5tvyzWm2jx8tWuTnW31sY2gWzKuuJAvTn9sDkXoWArAE4LB3kgU3KG4NBjDHd8S4T+KXLvKgxaGLRkv3w2ASuRm1sLvzzXUL8ho2WEows4uNZmEnEcQ07/PlV0lc8Gjm4EpI5MSUnJD8ZyYIya3k9nt11l31HHv/5ivI2gVMapy/jDxPfxK/5NsP7wiO+oMecq5+J/AAAA//+8ajHdJAIAAA==
          mode: 493
          path: /usr/local/bin/oci-eval-user-data.sh
    systemd:
      units:
        - contents: |
            [Unit]
            Description=Evaluate user data
            ConditionFirstBoot=yes
            After=NetworkManager.service
            Before=ovs-configuration.service kubelet.service

            [Service]
            ExecStart=/usr/local/bin/oci-eval-user-data.sh
            Type=oneshot
            RemainAfterExit=yes
            Restart=on-failure
            RestartSec=5

            [Install]
            WantedBy=multi-user.target
          enabled: true
          name: oci-eval-user-data.service
---
# Generated by Butane; do not edit
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 00-worker-oci-eval-user-data
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - contents:
            compression: gzip
            source: data:;base64,H4sIAAAAAAAC/3SRQY/aMBCF7/4VD5cDHIyBBqSicGgPqIeK/gQ0SSaNpcROHSeCtvz3KrBhw2r3lEjjed97bz5NdNt4nRir2XZIqCmEaDhAcXt2qE3NOZlSCJNjgrZhf8oo0CnZRvvpLG19CfUd8msbCufNHwrG2R2+MXn2+OkpLVlCqYrOKpiK8XkJpTwHf8Fm+FMZl3QZjVTqrPWctw1nUD9QhFDvtF5tvyzWm2jx8tWuTnW31sY2gWzKuuJAvTn9sDkXoWArAE4LB3kgU3KG4NBjDHd8S4T+KXLvKgxaGLRkv3w2ASuRm1sLvzzXUL8ho2WEows4uNZmEnEcQ07/PlV0lc8Gjm4EpI5MSUnJD8ZyYIya3k9nt11l31HHv/5ivI2gVMapy/jDxPfxK/5NsP7wiO+oMecq5+J/AAAA//+8ajHdJAIAAA==
          mode: 493
          path: /usr/local/bin/oci-eval-user-data.sh
    systemd:
      units:
        - contents: |
            [Unit]
            Description=Evaluate user data
            ConditionFirstBoot=yes
            After=NetworkManager.service
            Before=ovs-configuration.service kubelet.service

            [Service]
            ExecStart=/usr/local/bin/oci-eval-user-data.sh
            Type=oneshot
            RemainAfterExit=yes
            Restart=on-failure
            RestartSec=5

            [Install]
            WantedBy=multi-user.target
          enabled: true
          name: oci-eval-user-data.service
---
EOT
}
