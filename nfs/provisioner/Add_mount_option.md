# NFS Provisioner에 mountoption 추가 방법.

1. 우선 다음과 같은 예시의 deployment.yaml, storageclass.yaml을 사용하여  nfs provisioner 4.0.2를 배포했다고 가정합니다.

```yaml
#before_deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: default
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: k8s-sigs.io/nfs-subdir-external-provisioner
            - name: NFS_SERVER
              value: 172.22.4.101
            - name: NFS_PATH
              value: /root/nfs_share
      volumes:
        - name: nfs-client-root
          nfs:
            server: 172.22.4.101
            path: /root/nfs_share

```

```yaml
#before_storageclass.yaml

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner # or choose another name, must match deployment's env PROVISIONER_NAME'
parameters:
  onDelete: delete
  archiveOnDelete: "false"

```

2. 이와 같은 상태에서 nfs-client-provisioner pod과 nfs pvc를 사용하는 pod은 다음과 같이 nfs4를 사용해 mount 하고 있습니다.
-  nfs-client-provisioner pod이 뜬 노드에서 확인
```sh
[root@node1 nfs_share]# mount | grep nfs_share
172.22.4.101:/root/nfs_share on /var/lib/kubelet/pods/eb6665b5-5571-4f53-84a3-ccffad5ea714/volumes/kubernetes.io~nfs/nfs-client-root type nfs4 (rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=172.22.4.101,local_lock=none,addr=172.22.4.101)
```
- nfs-pvc 사용 pod에서 확인
```sh
root@nfs-demo-pod:/var/lib/www/html# mount | grep nfs_share
172.22.4.101:/root/nfs_share/default-nfs-pvc-pvc-b335a751-017a-4cdb-8de6-00e94406447f on /var/lib/www/html type nfs4 (rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=172.22.4.102,local_lock=none,addr=172.22.4.101)
```
3. nfs v3으로 변경을 위해 nfs-client-provisioner삭제 후 재배포 및 storageclass를 수정해야 합니다.


- [link](README.md)를 참조하여 다음과 같이 새로운 yaml을 준비합니다. 

```yaml
#new_deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: default
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: k8s-sigs.io/nfs-subdir-external-provisioner
            - name: NFS_SERVER
              value: 172.22.4.101
            - name: NFS_PATH
              value: /root/nfs_share
### 여기서부터 변경
      volumes:
        - name: nfs-client-root
          persistentVolumeClaim:
            claimName: nfs-root-pvc
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-root-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  storageClassName: ""

### mountOption 추가.
  mountOptions:
  - hard
  - nfsvers=3
  claimRef:
    name: nfs-root-pvc
    namespace: default
  nfs:
    # REPLACE with your nfs server
    server: 172.22.4.101
    # REPLACE with your nfs exported path
    path: /root/nfs_share
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-root-pvc
  namespace: default
spec:
  storageClassName: ""
  volumeName: nfs-root-pv
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

```yaml
#new_storageclass.yaml

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner # or choose another name, must match deployment's env PROVISIONER_NAME'
parameters:
  onDelete: delete
  archiveOnDelete: "false"
### mountOption 추가
mountOptions:
  - hard
  - nfsvers=3

```

4. 기존 deployment 삭제 후, deployment 재배포 및 storageclass 업데이트를 수행합니다.
```sh
[root@node1 nfs_share]# kubectl delete -f before_deployment.yaml
[root@node1 nfs_share]# kubectl apply -f new_deployment.yaml
[root@node1 nfs_test]# kubectl apply -f new_storageclass.yaml
storageclass.storage.k8s.io/nfs configured
```
5. nfs-client-provisioner pod이 nfs vers=3 쓰는지 확인
```sh
[root@node1 ~]# mount | grep nfs_share
172.22.4.101:/root/nfs_share on /var/lib/kubelet/pods/38233815-f91a-405b-98a6-4b6b1c46a329/volumes/kubernetes.io~nfs/nfs-root-pv type nfs (rw,relatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=172.22.4.101,mountvers=3,mountport=20048,mountproto=udp,local_lock=none,addr=172.22.4.101)
```
6. 새로 생성한 pod 들이 nfs vers=3 쓰는지 확인
```sh
[root@node1 nfs_test]# kubectl exec -it nfs-demo-pod2-fd988b5b5-g5fxw -- /bin/bash
root@nfs-demo-pod2-fd988b5b5-g5fxw:/# mount | grep nfs_share
172.22.4.101:/root/nfs_share/default-nfs-pvc2-pvc-f56d89c0-834a-472b-96c3-8adcbd8ee169 on /var/lib/www/html type nfs (rw,relatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=172.22.4.101,mountvers=3,mountport=20048,mountproto=udp,local_lock=none,addr=172.22.4.101)
```

7. 앞으로 생성할 pvc 들은 확인한 것과 같이 nfs vers=3 으로 mount 되겠지만, 이미 생성되어 있던 pv 및 pv를 사용하는 pod은 kubectl edit pv를 통해 직접 수정한 후, pod을 재시작 시켜야합니다.

- kubectl edit pv를 통한 pv 수정.
```sh
[root@node1 nfs_test]# kubectl edit pv pvc-b335a751-017a-4cdb-8de6-00e94406447f
```
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: k8s-sigs.io/nfs-subdir-external-provisioner
  creationTimestamp: "2022-10-17T07:17:44Z"
  finalizers:
  - kubernetes.io/pv-protection
  name: pvc-b335a751-017a-4cdb-8de6-00e94406447f
  resourceVersion: "1298011"
  selfLink: /api/v1/persistentvolumes/pvc-b335a751-017a-4cdb-8de6-00e94406447f
  uid: 9cd70a62-5da4-4f47-a5dd-4ae7a5656ec9
spec:
### mountOptions 추가.
  mountOptions:
  - hard
  - nfsvers=3
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 1Gi
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: nfs-pvc
    namespace: default
    resourceVersion: "1298006"
    uid: b335a751-017a-4cdb-8de6-00e94406447f
  nfs:
    path: /root/nfs_share/default-nfs-pvc-pvc-b335a751-017a-4cdb-8de6-00e94406447f
    server: 172.22.4.101
  persistentVolumeReclaimPolicy: Delete
  storageClassName: nfs
  volumeMode: Filesystem
status:
  phase: Bound
```

- POD 재시작
```sh
[root@node1 nfs_test]# kubectl delete pod nfs-demo-pod-5fd986d974-vb9b4
pod "nfs-demo-pod-5fd986d974-vb9b4" deleted

[root@node1 nfs_test]# kubectl get pod -owide
NAME                                     READY   STATUS    RESTARTS   AGE     IP           NODE    NOMINATED NODE   READINESS GATES
nfs-demo-pod-5fd986d974-r52tg            1/1     Running   0          8s      10.0.1.134   node2   <none>           <none>
```
- nfs vers=3 변경 확인
```sh
[root@node2 ~]# mount | grep nfs_share
172.22.4.101:/root/nfs_share/default-nfs-pvc-pvc-b335a751-017a-4cdb-8de6-00e94406447f on /var/lib/kubelet/pods/cd3ebfa1-d282-4bcd-9b9b-ddb0aa56cdc5/volumes/kubernetes.io~nfs/pvc-b335a751-017a-4cdb-8de6-00e94406447f type nfs (rw,relatime,vers=3,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=172.22.4.101,mountvers=3,mountport=20048,mountproto=udp,local_lock=none,addr=172.22.4.101)
```