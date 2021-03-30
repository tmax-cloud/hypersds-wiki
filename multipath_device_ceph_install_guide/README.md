## ceph osd를 pvc를 이용하여 배포하는 방법

- 해당 문서는 multipath device 위에 local pv를 생성한 후, 해당 pv 위에 osd를 생성하는 방법을 설명합니다.

### 주의 사항
- centos, prolinux 환경에서는 해당 방법으로 osd를 성공적으로 생성하기 위해 rook operator를 배포하는 operator.yaml에서 특정 feature를 키셔야합니다.
```yaml
        - name: ROOK_HOSTPATH_REQUIRES_PRIVILEGED
          value: "true" #true로 변경
```

### local pv 생성 방법

1. local-storage storageclass 배포
- `kubectl apply -f sc-local.yaml`
	- `kubectl get sc` 를 통해 정상 배포 여부를 확인할 수 있습니다.

2. local pv 생성

- 먼저 pv를 생성할 multipath device의 path를 확인합니다.
```shell
# lsblk로 보면 2개 device들 밑에 mpath가 보이는데 해당 name이 multipath device 입니다.

root@worker1:~# lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
...
sde      8:64   0  100G  0 disk
└─360000000000000000e00000000010001
       253:0    0  100G  0 mpath
sdf      8:80   0  100G  0 disk
└─360000000000000000e00000000010001
       253:0    0  100G  0 mpath

# fdisk -l을 통해 해당 multipath device의 path를 볼 수 있습니다.
# ex: /dev/mapper/360000000000000000e00000000010001
	   
root@worker1:~# fdisk -l
.....
Disk /dev/mapper/360000000000000000e00000000010001: 100 GiB, 107374182400 bytes, 209715200 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```
-  multipath device path 상에 local pv 생성
	- pv-volume.yaml 파일을 수정하고, 배포합니다.
		- ex: node3 host의 /dev/mapper/360000000000000000e00000000010001  
	- 해당 방법을 통해 osd를 띄울 모든 multipath device들에 미리 pv를 다 생성해줍니다.
```yaml
# pv-volume.yaml

apiVersion: v1
kind: PersistentVolume
metadata:
  name: example-pv-volume
spec:
  capacity:
    storage: 100Gi # directory 혹은 disk 크기
  volumeMode: Block
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain # device 는 수동으로 초기화해야 하므로 Retain 으로 두었습니다. pvc 를 삭제하는 경우 pv status 는 failed 가 되지만, 이는 큰 문제가 아니며 관리자가 해당 pv 와 mapping 된 device 를 수동으로 초기화한 후 pv 를 삭제하시면 됩니다.
  storageClassName: local-storage # storageclass 명시
  local:
    path: /dev/mapper/360000000000000000e00000000010001 # 백엔드 스토리지용으로 사용할 특정 노드의 특정 dir 혹은 device 명시
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node3 # kubectl get nodes 에서 해당하는 node name
```

### cluster.yaml에서 osd를 pvc base로 생성
- 기존에 `spec.storage.nodes`를 통해 직접 device를 명시해준 것과 달리 `spec.storage.storageClassDeviceSets`를 통해 osd 배포 개수 및 배포할 pvc spec을 명시해줄 수 있습니다.
- 기존에는 osd의 resource 제한을 `spec.resources.osd`를 통해서 해줬었으나, pvc 기반 osd에 resource 제한을 주기 위해서는 예시와 같이 `spec.storage.storageClassDeviceSets` 밑의 `resources`에서 제한을 해주셔야합니다.
- 예시는 다음과 같습니다. (cluster.yaml 참조)
	- 해당 예시의 경우 storageclass로 위에서 생성한 `local-storage`를 사용하였기에 cluster.yaml에 정의된 spec으로 생성된 pvc들은 multipath device path 위의 local pv들과 최종적으로 mapping됩니다.
	- 예시에서는 최종적으로 100Gi pvc 2개, 50Gi pvc 1개가 생성되고, 각 pvc 위에 osd가 생성되어 총 3개의 osd가 생성됩니다.
```yaml
###cluster.yaml 일부
...
################################
#### 기존과 다름
  storage:
    storageClassDeviceSets:
    # 100Gi pvc 2개 생성하고, osd 2개 생성하는 set
    - name: set1
      count: 2 # osd 및 pvc 생성 개수
      resources: #osd resource 제한 설정, 기존과 달리 osd에 resource 제한은 여기에서 줘야함
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      portable: false
      encrypted: false
      volumeClaimTemplates: #pvc spec 명시
      - metadata:
          name: data #이와 같이 하면, 나중에 osd가 생성될 pvc는 다음과 같은 이름으로 설정됩니다. set1-data-*-******
        spec:
          resources:
            requests:
              storage: 100Gi #100Gi pvc 생성
          storageClassName: local-storage #storageclass 명시
          volumeMode: Block
          accessModes:
          - ReadWriteOnce
    # 50Gi pvc 1개 생성하고, osd 1개 생성하는 set
    - name: set2
      count: 1 # osd 및 pvc 생성 개수
      resources: #osd resource 제한 설정, 기존과 달리 osd에 resource 제한은 여기에서 줘야함
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      portable: false
      encrypted: false
      volumeClaimTemplates: #pvc spec 명시
      - metadata:
          name: data #이와 같이 하면, 나중에 osd가 생성될 pvc는 다음과 같은 이름으로 설정됩니다. set2-data-*-******
        spec:
          resources:
            requests:
              storage: 50Gi #50Gi pvc 생성
          storageClassName: local-storage #storageclass 명시
          volumeMode: Block
          accessModes:
          - ReadWriteOnce

################################
```

### 이후 local pv 삭제 방법

#### 주의 사항
- storageclass 의 reclaimPolicy 를 Retain 으로 설정하였으므로 pv 삭제는 pvc 삭제 시 자동으로 삭제되지 않고 수동으로 삭제해야 합니다.
	- pvc 가 삭제되면 해당 pvc 와 bound 되었던 pv 의 STATUS 는 Bound 에서 Released 로 변경됩니다.
	- 해당 pv 의 삭제 방법은 다음과 같습니다.
		- `kubectl delete -f pv.yaml` (pv.yaml : 해당 pv 생성 시 사용하였던 yaml)
		- `kubectl get pv` 로 해당 pv 가 삭제된 것을 확인합니다.
		- 해당 pv.yaml 의 spec.local.path 를 직접 cleanup 해줍니다.
			- device 라면 device 초기화를 진행해야 하며
			- directory 라면 해당 directory 를 삭제하셔야 합니다.
- 해당 storageclass 로 생성한 모든 pvc, pv 가 삭제된 후, sc 를 삭제합니다.