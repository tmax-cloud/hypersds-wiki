# NFS Provisioner 배포 및 사용 가이드

기존에 사용하는 NFS 서버로 K8s cluster의 pv, pvc를 dynamic provisioning 하는 방법으로 본 가이드에 사용하는 nfs provisioner는 kubernetes-sigs group 내에서 개발 및 관리되고 있는 [NFS Subdir External Provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) 입니다. 

## 목차

- [전제조건](#Prerequisites)
- [배포 가이드](#배포-가이드)
- [사용 가이드](#사용-가이드)
- [삭제 가이드](#삭제-가이드)

## 구성 요소 및 버전

- NFS Subdir External Provisioner v4.0.0

### 도커 이미지 버전

- gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0

## Prerequisites

1. 본 가이드에서는 이미 NFS 서버가 존재하며 NFS provisioner를 배포할 k8s 환경과 통신이 가능함을 가정합니다.
2. k8s 클러스터의 모든 노드에는 `nfs-utils` 패키지 설치가 필요합니다.
    - taint 나 toleration property를 사용하는 경우에는 nfs 서버를 통해 volume provisioning 기능 제공할 k8s 노드에만 해당 패키지를 설치해주셔도 됩니다.
3. NFS 서버사용을 위해 사전에 필요한 접속 정보들은 아래와 같습니다.
    - NFS server hostname
    - NFS server exported path
4. NFS server exported path 내에 생성될 sub directory의 패턴에 대해 미리 정의 및 논의가 필요합니다.
    - **helm 차트를 사용할 경우에는 sub directory 패턴을 사용자 지정할 수 없습니다.**
      - 해당 기능이 master branch에 구현 되었으나 아직 릴리즈되지 않아서 릴리즈 후 재 가이드 예정입니다.
    - helm 차트 사용시 지정된 **기본값**: `{namespace-pvcName-pvName}/`
      - nfs 서버 내에서 pvc 마다 위의 이름 패턴으로 directory가 생성됩니다.
    - yaml 배포시 권장하는 **기본값**: `{namespace}/{pvcName}/`
      - namespace directory 아래 pvc 별로 directory가 생성되어 nfs 서버 내 데이터 관리가 용이할 수 있습니다.

## 폐쇄망 구축 가이드

- nfs-subdir-external-provisioner 도커 이미지를 미리 준비합니다.
- nfs-subdir-external-provisioner 배포 yaml를 미리 준비합니다.

작업 디렉토리 생성 및 환경 설정

``` shell
$ mkdir -p ~/nfs-install
$ export NFS_HOME=~/nfs-install
$ export NFS_PROVISIONER_VERSION=v4.0.0
$ cd $NFS_HOME
```

외부 네트워크 통신이 가능한 환경에서 도커 이미지를 다운로드

``` shell
$ sudo docker pull gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:${NFS_PROVISIONER_VERSION}
$ sudo docker save gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:${NFS_PROVISIONER_VERSION} > nfs_${NFS_PROVISIONER_VERSION}.tar
```

배포 yaml 다운로드

``` shell
$ git clone https://github.com/tmax-cloud/hypersds-wiki.git
$ mv hypersds-wiki/nfs/provisioner/deploy/ .
$ rm -rf hypersds-wiki/
```

다운로드 받은 파일들을 폐쇄망 환경으로 이동시킨 뒤 사용하려는 registry에 이미지를 push

``` shell
$ sudo docker load < nfs_${NFS_PROVISIONER_VERSION}.tar

$ export REGISTRY=123.456.789.00:5000
$ sudo docker tag gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:${NFS_PROVISIONER_VERSION} ${REGISTRY}/gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:${NFS_PROVISIONER_VERSION}

$ sudo docker push ${REGISTRY}/gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:${NFS_PROVISIONER_VERSION}
```

## 배포 가이드

sample yaml 설정들의 **기본값**은 아래와 같습니다.

- namespace: nfs
- storageclass 이름: nfs
- pvc delete 시에 nfs 서버 내 directory 삭제 여부: 삭제

### Helm 사용할 경우

- nfs server 주소와 exported path, provisioner를 배포할 k8s namespace를 명시하여 helm chart를 설치합니다.
- 예시에 정의된 필드 외에 다른 기본값 변경이 필요한 특수한 경우에는 [이 configuration table](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/tree/master/charts/nfs-subdir-external-provisioner#configuration)에서 parameter 확인이 가능합니다.
- `archiveOnDelete`를 `true`로 설정하는 경우에는 `archived-` 라는 prefix가 directory 이름에 추가되고, directory 내 데이터는 nfs server 내에 계속 존재하게 됩니다.

``` shell
$ helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
$ helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.7.16 \
    --set nfs.path=/mnt/nfs-shared-dir \
    --set storageClass.name=nfs \
    --set storageClass.archiveOnDelete=false \
    --namespace nfs \
    --create-namespace
```

### Helm 사용하지 않는 경우

1. provisioner를 배포할 k8s namespace로 치환하여 namespace와 rbac 관련 리소스를 먼저 배포합니다.

``` shell
$ NS={배포할 namespace name}
$ NAMESPACE=${NS:-nfs}

$ sed -i'' "s/name:.*/name: $NAMESPACE/g" ./deploy/namespace.yaml
$ sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./deploy/rbac.yaml ./deploy/deployment.yaml

$ kubectl apply -f deploy/namespace.yaml
$ kubectl apply -f deploy/rbac.yaml
```

2. nfs server 정보를 `deployment.yaml` 에 기입하여 provisioner를 배포합니다. nfs server 와 path key 값에 대한 value 값을 적어주시면 됩니다. 

``` yaml
# deploy/deployment.yaml
          env:
            - name: PROVISIONER_NAME
              value: k8s-sigs.io/nfs-subdir-external-provisioner
            - name: NFS_SERVER
              # REPLACE with your nfs server
              value: 192.168.7.16
            - name: NFS_PATH
              # REPLACE with your nfs exported path
              value: /mnt/nfs-shared-dir
      volumes:
        - name: nfs-client-root
          nfs:
            # REPLACE with your nfs server
            server: 192.168.7.16
            # REPLACE with your nfs exported path
            path: /mnt/nfs-shared-dir
```

``` shell
$ kubectl apply -f deploy/deployment.yaml
```

3. storageclass를 배포합니다. `class.yaml` 에서 storageclass 이름이나 pvc delete 시에 nfs server 내 폴더 삭제 여부, sub directory 생성 패턴 등을 설정 할 수 있습니다. 

    - nfs server 내 sub directory 생성 패턴 **기본값**: `{namespace}/{pvcName}/`
      - **유의사항**: hierarchy가 존재하는 sub directory를 생성할 경우에, pvc 삭제시 데이터가 저장되는 바로 상위 directory만 삭제됩니다. 
      - 위와 같이 설정을 적용할 경우에는  `onDelete`가 `delete`로 설정 되어 있어도, namespace directory는 nfs 서버내에 존재합니다.
    - `onDelete`를 `retain`으로 설정할 경우 pvc 삭제 후에도 nfs 서버 내에는 데이터가 존재합니다.

``` yaml
# deploy/class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
# provisioner name must match deployment's env PROVISIONER_NAME'
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner
parameters:
  # set 'retain' if you want to save the directory
  onDelete: delete
  # you can set nfs subdirectory path pattern
  pathPattern: "${.PVC.namespace}/${.PVC.name}"
```

``` shell
$ kubectl apply -f deploy/class.yaml
```

### 여러개의 NFS 서버를 사용하는 경우

> 볼륨 프로비저닝을 위한 NFS 서버를 추가하거나, 여러개의 NFS 서버를 사용하고자 하는 경우에는 NFS 서버 마다 provisioner 와 storage class 추가 생성이 필요합니다.

#### Helm 사용할 경우

- 이미 배포된 namespace와 rbac 관련 리소스는 그대로 사용하실 수 있습니다.
- unique한 nfs provisioner 이름 지정이 필요하고, 사용할 nfs 서버 정보를 기입하여 주시면 됩니다.

``` shell
$ helm install nfs-provisioner-2 nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.7.17 \
    --set nfs.path=/mnt/nfs-shared-dir \
    --set storageClass.name=nfs2 \
    --set storageClass.archiveOnDelete=false \
    --set storageClass.provisionerName=nfs-provisioner-2 \
    --set serviceAccount.create=false \
    --set serviceAccount.name=nfs-client-provisioner \
    --set rbac.create=false \
    --namespace nfs
```

#### Helm 사용하지 않는 경우

1. 이전 과정에서 배포된 namespace와 rbac 관련 리소스는 그대로 사용하실 수 있습니다. 별도로 추가 생성은 필요하지 않습니다.
2. `deployment.yaml` 에서 다른 nfs provisioner와 겹치지 않은 unique 한 provisioner 이름과 사용할 nfs server 정보를 기입합니다.

``` yaml
# deploy/deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  # k8s deployment 이름 변경 필요
  name: nfs-client-provisioner2
  labels:
    app: nfs-client-provisioner
# (중략) ...
          env:
            - name: PROVISIONER_NAME
              # unique한 provisioner 이름으로 변경 필요
              value: nfs-subdir-external-provisioner
            - name: NFS_SERVER
              # REPLACE with your nfs server
              value: 172.22.4.222
            - name: NFS_PATH
              # REPLACE with your nfs exported path
              value: /mnt/nfs-shared-dir
      volumes:
        - name: nfs-client-root
          nfs:
            # REPLACE with your nfs server
            server: 172.22.4.222
            # REPLACE with your nfs exported path
            path: /mnt/nfs-shared-dir
```

``` shell
$ kubectl apply -f deploy/deployment.yaml
```

3. `class.yaml` 에서 provisioner 이름을 `deployment.yaml` 에서 정의한 env `PROVISIONER_NAME` 값과 동일하게 기입합니다.

``` yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  # storage class 이름 변경 필요
  name: nfs2
# provisioner name must match deployment's env PROVISIONER_NAME'
provisioner: nfs-subdir-external-provisioner
parameters:
  # set 'retain' if you want to save the directory
  onDelete: delete
  # you can set nfs subdirectory path pattern
  pathPattern: "${.PVC.namespace}/${.PVC.name}"
```

``` shell
$ kubectl apply -f deploy/class.yaml
```

### nfs mount option이 별도로 지정 필요한 경우

- `deployment.yaml` 과 `class.yaml` 변경이 필요합니다.

`deploymnet.yaml` 기본 설정의 경우에는 nfs provisioner 생성시에 nfs volume을 생성 하는데, 이 경우에는 `sec option`과 같은 nfs mount 옵션 설정이 불가합니다. nfs server 설정에 따라 nfs mount option 설정이 필요한 경우에는 nfs volume이 아닌 pv, pvc를 생성하는 것으로 `deploymnet.yaml` 수정이 필요합니다.

``` yaml
# deploy/deployment.yaml
# (중략) ...
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
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  mountOptions:
    - sec=none
  claimRef:
    name: nfs-root-pvc
    namespace: nfs
  nfs:
    # REPLACE with your nfs server
    server: 192.168.7.16
    # REPLACE with your nfs exported path
    path: /mnt/nfs-shared-dir
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-root-pvc
  namespace: nfs
spec:
  storageClassName: ""
  volumeName: nfs-root-pv
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
```

`class.yaml`에서는 추가 할 mountOption 기입이 필요합니다.

``` yaml
# deploy/class.yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
# provisioner name must match deployment's env PROVISIONER_NAME'
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner
parameters:
  # set 'retain' if you want to save the directory
  onDelete: delete
  # you can set nfs subdirectory path pattern
  pathPattern: "${.PVC.namespace}/${.PVC.name}"
  mountOptions:
    - sec=none
```

## 사용 가이드

1. pvc 생성

``` shell
$ kubectl apply -f deploy/test-claim.yaml
```

2. pod 생성

``` shell
$ kubectl apply -f deploy/test-pod.yaml
```

## 삭제 가이드 

- nfs provisioner를 삭제하기 전 해당 provisioner를 사용하여 생성된 자원은 지워주셔야 합니다.

``` shell
$ kubectl delete -f deploy/test-pod.yaml
$ kubectl delete -f deploy/test-claim.yaml
```

### Helm 사용한 경우

``` shell
$ helm uninstall nfs-subdir-external-provisioner --namespace nfs
```

### Helm 사용하지 않은 경우

``` shell
$ kubectl delete -f deploy/class.yaml
$ kubectl delete -f deploy/deployment.yaml
$ kubectl delete -f deploy/rbac.yaml
$ kubectl delete -f deploy/namespace.yaml
```
