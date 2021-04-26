# oVirt에 MBS 설정 및 사용 가이드

## 목차

- [Cinderlib 활성화 가이드](#Cinderlib-활성화)
- [패키지 설치 가이드](#패키지-설치-가이드)
- [Ceph cluster 연결 가이드](#Ceph-cluster-연결-가이드)
- [MBS 활성화 가이드](#MBS-활성화-가이드)
- [MBS 사용 가이드](#MBS-사용-가이드)

## 구성 요소 및 버전

- Prolinux-8.2.2 + openstack 설치를 위한 repository (Prolinux팀에서 제공)
- oVirt 4.4.3.11-1.0.1.el8 (self-hosted engine + nfs storage domain 사용)

## Cinderlib 활성화

- Cinderlib 활성화는 cinderlib이 사용하는 데이터베이스를 설치하기 위함입니다.
  - Standalone으로 engine을 설치 할 경우 설치 과정에서 cinderlib 설정이 가능합니다.
  - Self-hosted로 engine을 설치 할 경우 설치 완료 후 [engine 재 설정 작업](#Engine-재-설정을-통한-cinderlib-활성화)을 통해 cinderlib 설정을 추가로 해주셔야 합니다.

### Engine 재 설정을 통한 cinderlib 활성화

- Prerequisite 
  > self-hosted engine을 설치한 worker 노드에서 진행
  - Engine 재 설정 시 mode를 global로 변경해야 하는 사전 작업이 필요합니다.
    ```shell script
    $ hosted-engine --set-maintenance --mode=global
    ```
    
  - Engine 재 설정 완료 후 mode 재 변경 부탁드립니다.
    ```shell script
    $ hosted-engine --set-maintenance --mode=none
    ```
    
- Engine 재 설정
  > engine 노드에서 진행
  - Cinderlib 관련 값 외에는 default로 설정하거나 필요에 따라 설정하시면 됩니다.
    ```shell script
    $ engine-setup --reconfigure-optional-components
    ```

    - Configure Cinderlib integration (Currently in tech preview) (Yes, No) [No]: yes

    - Where is the ovirt cinderlib database located? (Local, Remote) [Local]: local

    - Setup can configure the local postgresql server automatically for the CinderLib to run. This may conflict with existing applications.
    Would you like Setup to automatically configure postgresql and create CinderLib database, or prefer to perform that manually? (Automatic, Manual) [Automatic]: automatic 

## 패키지 설치 가이드

> 패키지가 존재하지 않을 시 prolinux 팀(CK 본부 CK2-2팀)에 문의 부탁드립니다.

- 모든 ovirt 노드에 openstack 패키지 설치
  ```shell script
  $ yum install openstack-cinder
  ```

- Engine 노드
  - cinderlib 관련 패키지 설치
    ```shell script
    $ pip3 install cinderlib==3.0.0
    $ pip3 install ntlm-auth
    ```

  - 설치 확인
    ```shell script
    $ pip3 show cinderlib
    $ pip3 show ntlm-auth
    ```

- 모든 Worker 노드
  - cinderlib 관련 패키지 설치
    ```shell script
    $ pip3 install os-brick
    $ pip3 install ntlm-auth
    ```
    
  - 설치 확인
    ```shell script
    $ pip3 show os-brick
    $ pip3 show ntlm-auth
    ```
    
  - vdsmd 재 시작
    ```
    $ systemctl restart vdsmd
    ```
    
## Ceph cluster 연결 가이드
- 모든 ovirt 노드에 ceph client 패키지 설치
  ```shell script
  $ yum install ceph-common
  ```
  
- 사용하고자 하는 ceph cluster의 정보를 모든 ovirt 노드에 복사
  - Ceph cluster가 설치 되어 있는 노드의 /etc/ceph 디렉토리에 있는 ceph config 파일(ceph.conf와 ceph.client.admin.keyring)들을 모든 ovirt 노드의 /etc/ceph 디렉토리에 복사

  - 파일 권한을 아래와 같이 확인 필요
  ```shell script
  [root@engine ceph]# ls -al
  total 24
  drwxr-xr-x.   2 root root   70 Apr 21 14:35 .
  drwxr-xr-x. 127 root root 8192 Apr 21 11:53 ..
  -rw-r--r--.   1 root root   63 Apr 21 14:35 ceph.client.admin.keyring
  -rw-r--r--.   1 root root  171 Apr 21 14:34 ceph.conf
  ```

## MBS 활성화 가이드
- Engine 노드에서 진행
  ```shell script
  $ engine-config -s ManagedBlockDomainSupported=true
  Please select a version:
  1. 4.2
  2. 4.3
  3. 4.4
  4. 4.5
  3
  ```
  
- Engine 재 시작
  ```shell script
  $ systemctl restart ovirt-engine
  ```
  
- 활성화 확인
  - Storage -> Domains -> New Domain 화면에서 Domain Function에 Managed Block Storage 항목이 존재하면 활성화 완료

## MBS 사용 가이드

- MBS storage domain 생성
  - Storage -> Domains -> New Domain
    - Name 입력
    - Domain Function을 Managed Block Storage로 선택
    - Driver Options
      - volume_driver: cinder.volume.drivers.rbd.RBDDriver
      - rbd_ceph_conf: /etc/ceph/ceph.conf
      - rbd_pool: mypool (ceph cluster에서 사용하고자 하는 rbd pool 이름)
      - rbd_user: admin
    - Driver Sensitive Options
      - rbd_keyring_conf: /etc/ceph/ceph.client.admin.keyring

- MBS disk 생성
  - Storage -> Disks -> New
    - Managed Block 탭 선택 후 size, alias 입력 후 생성

- VM 생성
  - oVirt에서 vm을 생성하기 위해 vm 이미지가 들어있는 disk가 필요합니다.
  - 이미지 disk를 만들기 위한 방법은 아래와 같습니다.
    - oVirt에서 제공하는 openstack glance에 존재하는 이미지를 import
    - 사용자가 upload
    
  - 하지만 현재  oVirt에서 MBS로 이미지 disk를 생성할 수 있는 방법이 없습니다.
    - MBS로는 empty disk 생성, 삭제, attach 가능합니다.

- 수동으로 MBS 이미지 disk 생성
  - oVirt에 MBS disk 생성
  - Raw 형식의 VM 이미지 준비 (현재까지 확인한바로는 qcow2 형식은 부팅 불가)
  - Ceph cluster에 연결할 수 있는 노드에서 작업 진행
    ```shell script
    $ rbd import {image-file} --dest-pool {pool-name}
    $ rbd rm {pool-name}/{volume-diskId}
    $ rbd mv {pool-name}/{image-file} {pool-name}/{volume-diskId}
    ```
