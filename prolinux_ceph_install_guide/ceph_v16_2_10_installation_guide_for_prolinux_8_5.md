# ProLinux 8.5 기준 CEPH v16.2.10 설치 가이드

작성자: 백승록 (Baek Seung Rok, CK2-4, seungrok_baek@tmax.co.kr)<br>
작성일: 2023. 02. 15<br>
참조: [HyperSDS-Wiki] - [ProLinux 8.2 기준 ceph v15.2.8 설치 간단 가이드](https://github.com/tmax-cloud/hypersds-wiki/blob/main/prolinux_ceph_install_guide/README.md)

***본 문서는 테스트 용도로 작성되었음을 알립니다.***

들어가기에 앞서, ProLinux Cluster 에서 테스트할 수 있는 환경이 없어 확실하게 모든 과정을 테스트 해보지 않고, 내용 수정 위주로 작성되었습니다. 고로, 설치 과정 중에 오류가 있을 수 있으니, 오류가 발생할 경우, 언제든지 문의 바랍니다.

- [1. 필수 패키지 설치](#1-필수-패키지-설치)
  - [1.1. yum 을 이용한 설치](#11-yum-을-이용한-설치)
  - [1.2. Docker Engine 설치](#12-docker-engine-설치)
- [2. CEPH 설치](#2-ceph-설치)
  - [2.1. cephadm / ceph-common 설치](#21-cephadm--ceph-common-설치)
  - [2.2. CEPH 설치](#22-ceph-설치)
- [3. CEPH 추가 설정](#3-ceph-추가-설정)
  - [3.1. 다른 노드를 ceph cluster에 추가](#31-다른-노드를-ceph-cluster에-추가)
  - [3.2. osd 추가](#32-osd-추가)
    - [3.2.1. 추가 가능 여부 확인](#321-추가-가능-여부-확인)
    - [3.2.2. 노드 단위로 osd 추가](#322-노드-단위로-osd-추가)
    - [3.2.3. CEPH Pool 생성 및 Replica size 1로 설정](#323-ceph-pool-생성-및-replica-size-1로-설정)
    - [3.2.4. cephfs mds daemon 배포](#324-cephfs-mds-daemon-배포)
    - [3.2.5. cephfs 생성](#325-cephfs-생성)
    - [3.2.6. 확인](#326-확인)
- [4. CEPH cluster 제거](#4-ceph-cluster-제거)
- [5. 문의 사항](#5-문의-사항)

# 1. 필수 패키지 설치

모든 설치는 root 권한으로 진행하여야 합니다.
`sudo -s` 를 이용하면 쉽게 root 권한 상태를 유지할 수 있습니다.<br>
\* `$` 이후의 명령어들을 복사 붙여넣기 하면 편합니다. (`$` 기호는 터미널 명령어라는 관례적 표시)

## 1.1. yum 을 이용한 설치

- 아래의 패키지는 CEPH 설치에 있어 반드시 필요하므로, CEPH를 설치할 모든 노드에서 Package 존재 유무 확인 및 설치해주시기 바랍니다. 없으면 설치 중 에러 발생.
    
    ```bash
    $ yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm # epel-release
    $ yum install -y kernel-devel kernel-headers make gcc elfutils-libelf-devel git lvm2 epel-release tar httpd yum-utils jq chrony openssh-clients gdisk coreutils util-linux
    $ systemctl restart chronyd    # chrony service 를 실행하여 시간 동기화
    ```
    
- Package Repository 정리

    | Package | Repository |
    | --- | --- |
    | kernel-devel | BaseOS |
    | kernel-headers | BaseOS |
    | make | BaseOS |
    | gcc | AppStream |
    | elfutils-libelf-devel | BaseOS |
    | git | AppStream |
    | lvm2 | BaseOS |
    | epel-release | @@commandline |
    | tar | BaseOS |
    | httpd | AppStream |
    | yum-utils | BaseOS |
    | jq | AppStream |
    | chrony | BaseOS |
    | openssh-clients | BaseOS |
    | gdisk | BaseOS |
    | coreutils | BaseOS |
    | util-linux | BaseOS |

## 1.2. Docker Engine 설치

- Set up Docker Repository
    
    ```bash
    # CentOS repo 에서 정상 동작하는 것 확인
    $ yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    ```
    
- Docker Engine 설치
    
    ```bash
    $ yum remove -y runc  # 혹시 모를 runc conflict 문제 예방 (podman 이 기존에 설치되어 있었을 경우)
    $ yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    $ service docker restart  # docker daemon start.
    ```
    

# 2. CEPH 설치

## 2.1. cephadm / ceph-common 설치

- Set up ceph repository (16.2.10)
    
    ```bash
    $ cat <<EOF | tee /etc/yum.repos.d/ceph.repo >> /dev/null
    [Ceph]
    name=Ceph $(rpm -q --qf "%{arch}" -f /etc/$distro)
    baseurl=https://download.ceph.com/rpm-16.2.10/el8/$(rpm -q --qf "%{arch}" -f /etc/$distro)
    enabled=1
    gpgcheck=1
    gpgkey=https://download.ceph.com/keys/release.gpg
    
    [Ceph-noarch]
    name=Ceph noarch
    baseurl=https://download.ceph.com/rpm-16.2.10/el8/noarch
    enabled=1
    gpgcheck=1
    gpgkey=https://download.ceph.com/keys/release.gpg
    
    [Ceph-source]
    name=Ceph SRPMS
    baseurl=https://download.ceph.com/rpm-16.2.10/el8/SRPMS
    enabled=1
    gpgcheck=1
    gpgkey=https://download.ceph.com/keys/release.gpg
    EOF
    ```
    
- cephadm 설치
    
    ```bash
    $ yum install -y cephadm ceph-common  # repo 설정으로 인하여 16.2.10 으로 설치될 것.
    ```
    

## 2.2. CEPH 설치

1. 설치 전 ceph를 설치할 노드들에 hostname 설정이 되어 있어야합니다.<br>
\* 제대로 되어 있지 않으면, 설치 실패 합니다.
    
    ```bash
    $ hostname localhost # host 이름을 localhost로 설정
    ```
    
2. bootstrap 명령어를 이용한 ceph 설치<br>
\* 위의 조건들을 제대로 지키지 않았다면, 설치 실패합니다.<br>
\** `monip` 에는 설치하고 있는 노드의 IP 주소를 적습니다.
    
    ```bash
    $ monip="192.168.6.175"
    $ cephadm --image quay.io/ceph/ceph:v16.2.10 bootstrap --mon-ip ${monip}
    ```
    
3. 여기까지 완료했다면, `cephadm`이 깔린 노드 하나에 CEPH를 설치한 것.
4. 설치 확인
    
    ```bash
    $ ceph orch ps --refresh
    $ ceph orch ls --refresh
    $ ceph -s
    ```
    

# 3. CEPH 추가 설정

## 3.1. 다른 노드를 ceph cluster에 추가

앞선 `cephadm`을 통한 ceph 설치 방법과 동일합니다. 아래 방법을 통해 노드를 ceph cluster에 추가해야 해당 노드에 ceph daemon들을 추후 설치할 수 있습니다.<br>
\* 참고: 모니터는 5개, mgr은 2개 (혹은 3개)가 기본 설정이라 노드를 추가하면 자동으로 해당 노드들에 ceph daemon(mon, mgr)을 배포합니다. 단, mon 간의 quorum 을 형성해야하므로 mon는 1개, 3개, 5개, ... 처럼 홀수개로 추가됩니다.

- Host 추가를 위해서는 먼저 아래의 명령을 통해 추가되는 노드에 ssh key 복사가 필요합니다.
    
    ```bash
    # ssh-copy-id -f -i /etc/ceph/ceph.pub root@*<new-host>*  
    $ ssh-copy-id -f -i /etc/ceph/ceph.pub root@192.168.72.100
    ```
    
- 명령어
    
    ```bash
    # ceph orch host add <hostname> <IP>
    $ ceph orch host add node1 192.168.72.100
    ```
    
- Host 추가 확인
    
    ```bash
    $ ceph orch host ls
    ```
    
- 참고
    - host 추가로 mon이 추가되는 경우, 기본적으로 각 노드에 있는 `ceph.conf` 파일이 수정되지는 않습니다. (`ceph.conf` 파일에 통신하기 위한 mon address들이 명시되어 있음)
    - 각 노드에 있는 ceph daemon들이나, 이미 사용하고 있는 client의 경우는 내부적으로 mon의 추가를 인식하고, 내부적으로 저장하기 때문에 문제 없습니다.
    - 그러나, 새로운 ceph client 생성시(재부팅 등의 경우도 포함)에는 `ceph.conf` 파일을 참조하기 때문에, 추가된 mon을 알지 못하며, `ceph.conf` 파일 내에 명시된 mon이 죽어 있는 경우는 연결이 되지 않는 경우가 발생할 수 있습니다.
    - 따라서, mon 추가된 경우, 다음 명령어를 통해 `ceph.conf`를 재생성하고, 이를 client 연결시 사용하시길 바랍니다.
        
        ```bash
        # config 파일 생성
        $ ceph config generate-minimal-conf > ceph.conf
        # admin 계정 ceph.client.admin.keyring 파일 생성
        $ ceph auth get client.admin > ceph.client.admin.keyring
        ```
        

## 3.2. osd 추가

### 3.2.1. 추가 가능 여부 확인

osd 추가는 disk 전체 사용을 전제로 하며, disk는 완벽하게 초기화(partition table, partition, lvm 있으면 안됨)가 되어 있어야 합니다.

- disk 초기화
    
    ```bash
    # disk는 /dev/sdb 가정
    $ sgdisk --zap-all /dev/sdb
    $ dd if=/dev/zero of=/dev/sdb bs=1M count=100 oflag=direct,dsync
    $ blkdiscard /dev/sdb
    
    # 이전에 ceph를 깐 적이 있는 노드라면 다음 커맨드 수행도 필요
    $ ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove %
    $ rm -rf /dev/ceph-*
    ```
    
- disk ceph 추가 가능 여부 확인
    
    ```bash
    # 해당 명령어 쳤을 때 초기화한 disk가 보여야됨
    $ ceph orch device ls --refresh
    ```

### 3.2.2. 노드 단위로 osd 추가

- 노드 별로 osd 배포를 위한 yaml 파일 생성
    
    ```bash
    # osd_localhost.yaml 파일
    service_type: osd		# osd로 고정
    service_id: osd_localhost	# 마음대로 설정, ex) osd_{hostname}
    placement:
      hosts:
      - localhost	# osd 배포할 hostname 명시
    data_devices:
      paths:
      - /dev/sdb	# osd 배포할 device 명시
      - /dev/sdc	# osd 배포할 device 명시
    ```
    
- yaml apply를 통해 osd 배포
    
    ```bash
    $ ceph orch apply osd -i osd_localhost.yaml
    ```
    
- 확인
    
    ```bash
    # osd 추가되었는지 확인
    $ ceph -s
    $ ceph osd status
    $ ceph osd tree
    ```
    

### 3.2.3. CEPH Pool 생성 및 Replica size 1로 설정

- 원래 replication size는 2나 3이 기본이지만, 최소환경 가정으로 1로 설정<br>
\* 참고, replica 1로 하면 `ceph -s`시 `HEALTH_WARN` 발생하는데, ceph cluster는 정상작동합니다.
    
    ```bash
    # replicapool : rbd pool
    # myfs-metadata, myfs-data0 : cephfs pool
    # device_health_metrics pool은 ceph cluster 생성시 존재, replica 1로 변경
    $ ceph osd pool set device_health_metrics size 1
    
    # rbd에 사용할 replicapool pool 생성 및 replica 1로 설정
    # 참고로 pool 생성 과정에서 pg_num,pgp_num 설정(항상 2의 배수로 설정해야함)을 최소 환경을 고려하여 최소로 하였는데, 기본적으로 환경이 클 경우 해당 숫자는 32 or 64 or 그 이상을 추천드립니다.
    # ceph osd pool create {poolname} {pg_num} {pgp_num} {replication mode}
    $ ceph osd pool create replicapool 32 32 replicated
    $ ceph osd pool set replicapool size 1
    $ rbd pool init replicapool
    # cephfs에 사용할 myfs-metadata, myfs-data0 pool 생성 및 replica 1로 설정까지 수행
    $ ceph osd pool create myfs-metadata 32 32 replicated
    $ ceph osd pool create myfs-data0 8 8 replicated
    $ ceph osd pool set myfs-metadata size 1
    $ ceph osd pool set myfs-data0 size 1
    ```
    

### 3.2.4. cephfs mds daemon 배포

```bash
# ceph orch apply mds {volumename: filesysetem name} --placement="1 {hostname}"
# 해당 방법 이외에 ceph fs volume create {volumename} {placement}을 통해서도 배포할 수는 있음
$ ceph orch apply mds myfs --placement="1 localhost"
```

### 3.2.5. cephfs 생성

```bash
# ceph fs new {volumename: filesysetem name} {medatadata pool} {data pool}
$ ceph fs new myfs myfs-metadata myfs-data0
```

### 3.2.6. 확인

```bash
$ ceph -s
$ ceph fs status
cephfs name : myfs
cephfs pool :
data pool : myfs-data0
metadata pool : myfs-metadata
rbd pool : replicapool
```

# 4. CEPH cluster 제거

***ceph cluster를 완전히 제거할 경우에만 사용바랍니다.***

1. ceph cluster의 fsid를 확인합니다. (`ceph -s` 또는 `ceph.conf`의 fsid 참고)
    
    ```bash
    $ ceph -s
    cluster:
        id:     239fd88c-c42b-11eb-8058-5254001ff4e5     # fsid
    ...
    $ cat /etc/ceph/ceph.conf
    [global]
        fsid = 239fd88c-c42b-11eb-8058-5254001ff4e5      # fsid
        mon_host = [v2:192.168.70.100:3300/0,v1:192.168.70.100:6789/0]
    ```
    
2. ceph daemon들이 배포된 모든 노드에 cephadm image를 다운로드합니다.<br>
\* 참고: [2.1. cephadm / ceph-common 설치](#21-cephadm--ceph-common-설치)
    
    처음 ceph 배포하는데 사용한 노드를 포함하여 host 추가를 통해 ceph에 추가시킨 모든 노드에 cephadm image를 다운로드합니다.
    
3. 모든 노드에서 `rm-cluster` 을 사용하여 ceph 데몬들을 제거합니다.
    
    해당 명령은 명령을 수행하는 노드의 /etc/ceph/ , /var/log/ceph, /var/lib/ceph 에 존재하는 현재 ceph cluster 데이터를 완전히 삭제합니다.
    
    또한 `systemctl`에 등록된 ceph daemon service 들을 삭제하여 노드에서 수행되는 ceph daemon들을 완전히 제거합니다.
    
    ```bash
    # rm-cluster 수행전에 systemctl에 등록된 ceph daemon을 확인하면 다음과 같이 ceph service들이 보입니다.
    $ systemctl | grep ceph
    ceph-239fd88c-c42b-11eb-8058-5254001ff4e5@mgr.master1.yxnhmf.service                                             loaded active running   Ceph mgr.master1.yxnhmf for 239fd88c-c42b-11eb-8058-5254001ff4e5
    ceph-239fd88c-c42b-11eb-8058-5254001ff4e5@mon.master1.service                                                    loaded active running   Ceph mon.master1 for 239fd88c-c42b-11eb-8058-5254001ff4e5
    ceph-239fd88c-c42b-11eb-8058-5254001ff4e5@node-exporter.master1.service                                          loaded active running   Ceph 
    ...
    ceph-239fd88c-c42b-11eb-8058-5254001ff4e5.target                                                                 loaded active active    Ceph cluster 239fd88c-c42b-11eb-8058-5254001ff4e5
    ceph.target                                                                                                      loaded active active    All Ceph clusters and services
    ```
    
    ```bash
    # ./cephadm rm-cluster --fsid {ceph-cluster fsid} --force
    $ ./cephadm rm-cluster --fsid 239fd88c-c42b-11eb-8058-5254001ff4e5 --force
    ```
    
    ```bash
    # rm-cluster 이후 systemctl에 등록되어 있는 ceph 관련 daemon 확인
    # 다음과 같이 ceph.target을 제외한 모든 service 제거 확인됨 (ceph.target만으로는 ceph daemon 생성하지 않음)
    $ systemctl | grep ceph
    ceph.target                                                                              loaded active     active          All Ceph clusters and services
    ```
    
4. osd로 사용된 디스크들의 재사용을 위해서는 초기화 과정이 필요합니다.<br>
\* 참고: [3.2.1. 추가 가능 여부 확인 - disk 초기화](#321-추가-가능-여부-확인)

# 5. 문의 사항

***본 문서는 테스트 용도로 작성되었음을 알립니다.***

실행 과정 중에 정상적으로 동작하지 않는 경우에는 언제든지 주저말고 문의 바랍니다.<br>
작성자: CK2-4 백승록 (seungrok_baek@tmax.co.kr)