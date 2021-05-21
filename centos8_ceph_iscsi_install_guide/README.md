# CentOS 8 기준 ceph-iscsi 설치 및 사용 가이드

## Notice & Prerequisite
- 해당 가이드의 모든 명령을 모두 root 권한으로 실행하여야 합니다.

- 모든 가이드는 [Ceph 공식 docs](https://docs.ceph.com/en/octopus/rbd/iscsi-overview/)를 참고하였고, 내용도 대동소이합니다.

- CentOS 8.2 기준으로 테스트 되었습니다.

- Ceph 및 iSCSI gateway로 사용할 **모든 노드**에서 `hostnamectl set-hostname {hostname}` 이나 DNS 단 설정 등의 방법으로 hostname 지정이 되어있어야 합니다.

- Hostname을 사용하여 노드와 통신하는 부분이 있기에, **모든 노드에서** /etc/hosts나 DNS에 `192.168.7.172 s1-1 / fe80::a00:27ff:fe2b:3df s1-1` 와 같이 **자신을 포함한 모든 노드**의 NIC ip를 확인하여 ipv4, ipv6를 등록하여 통신할 수 있도록 해야 합니다.

- Ceph 및 iSCSI 등이 사용하는 port들이 열려있는지 네트워크 장비 및 노드에서의 방화벽을 확인하여야 합니다.

- 연동할 Ceph가 이미 구성되어 있다고 가정합니다.

- Ceph 15.2.8 기준으로 테스트 되었습니다.

- Ceph 및 iSCSI gateway로 사용할 모든 노드의 `/etc/ceph/`에 동일한 Ceph 클러스터를 바라보는 `ceph.client.admin.keyring, ceph.conf, ceph.pub` 파일들이 공유되어 있어야 합니다.

- Ceph 클러스터에 **rbd 이름을 가진 pool**이 만들어져 있어야 합니다.

- ceph-iscsi(gwcli)를 설치할 때, HA를 위해 iSCSI gateway 노드가 2대 이상 있어야 합니다.

- [아래 2개의 repository](#repository)에 접근이 필요합니다.

## Initiator timeout을 막기 위한 Ceph 세팅
- iSCSI initiator가 timeout 되는 것을 방지하기 위해 Ceph 단에서 heartbeat 세팅을 해 주는 것이 좋습니다.
    ```
    # Ceph 명령어를 사용할 수 있는 아무 노드에서 한번 실행

    $ ceph tell osd.* config set osd_heartbeat_grace 20
    $ ceph tell osd.* config set osd_heartbeat_interval 5
    ```

## iSCSI Target 구성하는 방법
1. tcmu-runner 및 ceph-iscsi 설치
    - iSCSI gateway를 사용할 모든 노드에서 실행하여야 합니다.
    ```
    $ yum install tcmu-runner
    $ yum install ceph-iscsi
    ```
2. gateway 세팅
    - iSCSI gateway를 사용할 모든 노드에서 실행하여야 합니다.
    - `/etc/ceph/iscsi-gateway.cfg` 에 해당 내용을 추가합니다.
    - 만약, gateway api 통신에 인증을 사용한다면, trusted_ip_list 항목에 접근허용할 노드의 ipv4, ipv6를 전부 기술해야 합니다.
    ```
    [config]
    # Name of the Ceph storage cluster. A suitable Ceph configuration file allowing
    # access to the Ceph storage cluster from the gateway node is required, if not
    # colocated on an OSD node.
    cluster_name = ceph

    # Place a copy of the ceph cluster's admin keyring in the gateway's /etc/ceph
    # drectory and reference the filename here
    gateway_keyring = ceph.client.admin.keyring


    # API settings.
    # The API supports a number of options that allow you to tailor it to your
    # local environment. If you want to run the API under https, you will need to
    # create cert/key files that are compatible for each iSCSI gateway node, that is
    # not locked to a specific node. SSL cert and key files *must* be called
    # 'iscsi-gateway.crt' and 'iscsi-gateway.key' and placed in the '/etc/ceph/' directory
    # on *each* gateway node. With the SSL files in place, you can use 'api_secure = true'
    # to switch to https mode.

    # To support the API, the bear minimum settings are:
    api_secure = false

    # Additional API configuration options are as follows, defaults shown.
    # api_user = admin
    # api_password = admin
    # api_port = 5001
    # trusted_ip_list = 192.168.0.10,192.168.0.11
    ```
3. gateway 및 api server service 등록, 시작 및 작동 확인
    - iSCSI gateway를 사용할 모든 노드에서 실행하여야 합니다.
    ```
    $ systemctl daemon-reload

    $ systemctl enable rbd-target-gw
    $ systemctl start rbd-target-gw

    $ systemctl enable rbd-target-api
    $ systemctl start rbd-target-api

    # 아래 서비스들이 잘 작동하는지 확인
    $ systemctl status tcmu-runner
    $ systemctl status rbd-target-api
    $ systemctl status rbd-target-gw
    ```
4. gwcli로 gateway 설정
    - iSCSI gateway를 사용할 한 노드에서만 실행하여야 합니다.
    - gwcli를 통한 target 생성이 아닌 targetcli나 rbd를 사용하여 생성, 변경, 삭제 시 gateway의 정상작동을 기대할 수 없습니다.
    - 해당 사항은 예시이며, 환경에 따라 세팅을 다르게 하여야 합니다.
    1. gateway cli 실행
        ```
        $ gwcli
        ```
    2. iSCSI target 생성
        ```
        $ /> cd /iscsi-target
        $ /iscsi-target> create iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw
        ```
    3. iSCSI gateway 생성
        - 첫번째 gateway는 반드시 gwcli를 실행하는 노드의 hostname과 IP이여야만 합니다.
        - gateway는 해당 노드를 포함하여 2개 이상 존재하여야 합니다.
        ```
        $ /iscsi-target> cd iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw/gateways
        $ /iscsi-target...-igw/gateways> create ceph-gw-1 10.172.19.21
        $ /iscsi-target...-igw/gateways> create ceph-gw-2 10.172.19.22
        ```
    4. RBD image 생성
        ```
        $ /iscsi-target...-igw/gateways> cd /disks
        $ /disks> create pool=rbd image=disk_1 size=90G
        ```
    5. initiator 생성
        ```
        $ /disks> cd /iscsi-target/iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw/hosts
        $ /iscsi-target...eph-igw/hosts> create iqn.1994-05.com.redhat:rh7-client
        ```
    6. client에 CHAP username, password 설정
        ```
        $ /iscsi-target...at:rh7-client> auth username=myiscsiusername password=myiscsipassword
        ```
    7. 클라이언트에 붙을 rbd image 추가
        ```
        $ /iscsi-target...at:rh7-client> disk add rbd/disk_1
        ```

## CentOS 8에서 iSCSI Initiator를 사용하여 iSCSI Target(Gateway)에 접근하는 방법
- Initiator는 iSCSI client라고도 볼 수 있습니다. VMware ESX, Windows, Linux 등 Initiator 구현체마다 설정하는 방법이 모두 다르기에, 사용하고자 하는 Initiator 및 multipath 매뉴얼을 참고하시기 바랍니다.

- CentOS 8에서 Initiator 사용하는 방법
    1. iSCSI initiator와 multipath 설치
        ```
        $ yum install iscsi-initiator-utils
        $ yum install device-mapper-multipath
        ```
    2. multipath 설정
        1. /etc/multipath.conf에 해당 내용 설정
            ```
            devices {
                device {
                    vendor                 "LIO-ORG"
                    hardware_handler       "1 alua"
                    path_grouping_policy   "failover"
                    path_selector          "queue-length 0"
                    failback               60
                    path_checker           tur
                    prio                   alua
                    prio_args              exclusive_pref_bit
                    fast_io_fail_tmo       25
                    no_path_retry          queue
                }
            }
            ```
        2. multipathd enable
            ```
            $ mpathconf --enable --with_multipathd y
            ```
        3. multipathd service 재시작
            ```
            $ systemctl reload multipathd
            ```
    3. /etc/iscsi/initiatorname.iscsi 설정
        ```
        ex) InitiatorName=iqn.1994-05.com.redhat:rh7-client
        ```
    4. /etc/iscsi/iscsid.conf 설정
        ```
        ...
        # To enable CHAP authentication set node.session.auth.authmethod
        # to CHAP. The default is None.
        node.session.auth.authmethod = CHAP

        # To configure which CHAP algorithms to enable set
        ...


        ...
        # To set a CHAP username and password for initiator
        # authentication by the target(s), uncomment the following lines:
        node.session.auth.username = myiscsiusername
        node.session.auth.password = myiscsipassword
        ...
        ```
    5. target discovery
        ```
        $ iscsiadm -m discovery -t st -p 192.168.7.171

        192.168.7.171:3260,1 iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw
        192.168.7.172:3260,2 iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw
        ```
    6. 타겟으로 로그인
        ```
        iscsiadm -m node -T iqn.2003-01.com.redhat.iscsi-gw:iscsi-igw -l
        ```
    7. mpath 확인
        ```
        $ multipath -ll

        360014055343fea81cdb42aab86ce6079 dm-3 LIO-ORG,TCMU device
        size=10G features='0' hwhandler='1 alua' wp=rw
        |-+- policy='service-time 0' prio=50 status=active
        | `- 3:0:0:0 sdb 8:16 active ready running
        `-+- policy='service-time 0' prio=10 status=enabled
          `- 4:0:0:0 sdc 8:32 active ready running
        ```

## Repository
1. ceph-iscsi.repo
    ```
    [ceph-iscsi]
    name=ceph-iscsi noarch packages
    baseurl=http://download.ceph.com/ceph-iscsi/3/rpm/el8/noarch
    enabled=1
    gpgcheck=1
    gpgkey=https://download.ceph.com/keys/release.asc
    type=rpm-md

    [ceph-iscsi-source]
    name=ceph-iscsi source packages
    baseurl=http://download.ceph.com/ceph-iscsi/3/rpm/el8/SRPMS
    enabled=0
    gpgcheck=1
    gpgkey=https://download.ceph.com/keys/release.asc
    type=rpm-md
    ```
2. tcmu-runner.repo
    ```
    [tcmu-runner]
    name=tcmu-runner packages for $basearch
    baseurl=https://4.chacra.ceph.com/r/tcmu-runner/master/06d64ab78c2898c032fe5be93f9ae6f64b199d5b/centos/8/flavors/default/$basearch
    enabled=1
    gpgcheck=0
    type=rpm-md

    [tcmu-runner-noarch]
    name=tcmu-runner noarch packages
    baseurl=https://4.chacra.ceph.com/r/tcmu-runner/master/06d64ab78c2898c032fe5be93f9ae6f64b199d5b/centos/8/flavors/default/noarch
    enabled=1
    gpgcheck=0
    type=rpm-md

    [tcmu-runner-source]
    name=tcmu-runner source packages
    baseurl=https://4.chacra.ceph.com/r/tcmu-runner/master/06d64ab78c2898c032fe5be93f9ae6f64b199d5b/centos/8/flavors/default/SRPMS
    enabled=1
    gpgcheck=0
    type=rpm-md
    ```
