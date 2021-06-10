# NFS 서버 구축 가이드

본 가이드는 Prolinux OS 환경에서 nfs 서버를 구축하는 방법을 기술하고 있습니다.

## 구성 요소

물리 호스트에 설치가 필요한 패키지입니다. 해당 패키지는 nfs server를 구축할 물리 호스트와 nfs server를 사용할 nfs client 호스트 모두 설치가 필요합니다.

- nfs-utils

## Prerequisites

1. 적절한 nfs 서버 설정 옵션에 대한 사전 정의가 필요합니다. 지원하는 export 옵션에 대해서는 [linux man page](https://linux.die.net/man/5/exports)를 참고 부탁드립니다. 해당 가이드에서는 그 중에서도 흔히 쓰이는 일부 옵션들만 포함하고 있습니다.

## 구축 가이드

1. 필수 패키지를 설치합니다.

```
# yum -y install nfs-utils
# systemctl enable nfs-server.service
# systemctl start nfs-server.service
```

2. export 할 디렉토리를 생성합니다. (없는 경우만)

해당 디렉토리 경로는 nfs 서버 설정 시 필요합니다.

```
# mkdir -p /mnt/nfs-shared-dir
# chown -R nobody:nobody /mnt/nfs-shared-dir
# chmod 777 /mnt/nfs-shared-dir
```

3. 생성한 디렉토리 경로를 명시하고, 적절한 서버 설정 옵션을 기입하여 nfs 서버를 설정합니다.

- rw
  - 기본값
  - 사용자가 read, write 모두 가능함
- ro
  - 사용자가 데이터 수정 불가하며 read만 가능함
- sync
  - 이전 요청이 수행 완료 될 때까지 새로운 요청에 대해서 응답 하지 않음
- no_subtree_check
  - 기본값
  - subtree checking을 하지 않는 옵션
    - subtree check란 nfs 서버에 요청이 있을때 마다 요청된 파일 경로의 존재 여부 뿐 아니라 해당 경로가 nfs 서버에서 실제로 exported 되었는지 여부를 검증함을 의미함
    - 즉 해당 옵션을 사용하면 nfs 서버에서 전체 파일시스템이 export 된 것이 아니라 subdirectory만 export 되었을 때, 원격 사용자의 요청이 export 된 subdirectory path 내에서 이뤄진 것이 맞는지 directory structure를 체크하지 않으며, 반대로 이 체크 과정을 수행하기 위해서는 `subtree_check` 값을 설정 할 수 있음
  - 하지만, 실 사용 시에 subtree_check 하게 되면, 파일이 다른 directory로 이동하며 이름이 변경된 경우에 file handle 관리 문제가 있기 때문에 nfs client 접근시 에러가 자주 발생하여 no_subtree_check 옵션을 권장함
- root_squash
  - nfs 서버 사용 시에 보안 및 안전상의 이유로 root privileges가 있는 원격 사용자가 가진 접근 권한을 억누르는 옵션
  - 기본값은 `all_squash`로 uid/gid 0인 root 사용자 뿐 아니라 모든 uid/gid 사용자를 `nfsnobody` 유저로 맵핑함
  - `root_squash`는 uid/gid 0인 root 사용자에 한해서만 `nfsnobody` UID를 할당함
  - 원격 사용자의 root 권한을 nfs 서버 사용시에 그대로 유지시키는 옵션으로는 `no_root_squash`를 사용할 수 있음
- sec=mode
  - nfs connection을 맺을 때 security 타입을 설정할 수 있음
  - 기본값: sec=sys

```
# vi /etc/exports

/mnt/nfs-shared-dir *(rw,sync,no_subtree_check)

# exportfs -a
```

4. [NFS Provisioner 배포 및 사용 가이드](../provisioner/README.md)를 참고하여 k8s 클러스터와 구축된 nfs 서버를 연동할 프로비저너를 배포합니다.

- provisioner 사용시에는 nfs client node에 별도로 nfs mount 할 필요 없습니다.
