# NFS Provisioner 배포 및 사용 가이드

기존에 사용하는 NFS 서버로 K8s cluster의 pv, pvc를 dynamic provisioning 하는 방법으로 본 가이드에 사용하는 nfs provisioner는 kubernetes-sigs group 내에서 개발 및 관리되고 있는 [NFS Subdir External Provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) 입니다. 

## 구성 요소 및 버전

- NFS Subdir External Provisioner v4.0.0

### 도커 이미지 버전

- gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0

## Prerequisites

1. 본 가이드에서는 이미 NFS 서버가 존재하며 NFS provisioner를 배포할 k8s 환경과 통신이 가능함을 가정합니다.
2. NFS를 사용할 k8s 클러스터 노드에는 `nfs-utils` 패키지 설치가 필요합니다.
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
