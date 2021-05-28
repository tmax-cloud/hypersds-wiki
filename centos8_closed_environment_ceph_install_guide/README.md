# centos8 기준 폐쇄망 ceph v15.2.8 설치 가이드
> 해당 가이드의 명령들은 모두 root로 실행해야 합니다.
## 필수 패키지
- 다음 패키지는 ceph 설치에 있어서 반드시 필요하므로, ceph clsuter를 구성하는 모든 노드에 설치해줘야 합니다. 
	- podman
	- chrony
		- ceph 설치할 노드 간에는 시간 동기화가 반드시 필요하니 chrony를 설치하시고, chrony를 통한 노드 간 시간동기화 설정까지 모두 반드시 해주셔야합니다.
	- lvm2
    - ceph-common (v15.2.8)
    ### 패키지 다운 방법
    > centos8 기준으로 패키지들을 다운받는 하나의 예시일 뿐이며, 다른 방법이 존재하시거나, 다른 os의 경우 다른 방법으로 진행해주시기 바랍니다.

    -  다른 방법 : https://github.com/tmax-cloud/install-pkg-repo
    
    > 폐쇄망에서 사용할 os와 완전히 같은 버전의 깨끗한 상태의 os(kernel 버전도 같음)에서 인터넷을 통해 해당 방법으로 필수 패키지들을 다운로드합니다.
    
    1. ceph-common 패키지를 위해 /etc/yum.repos.d 에 다음 내용의 ceph.repo 파일 추가
		```
		# ceph.repo

		[Ceph]
		name=Ceph $basearch
		baseurl=https://download.ceph.com/rpm-15.2.8/el8/$basearch
		enabled=1
		gpgcheck=1
		gpgkey=https://download.ceph.com/keys/release.asc
		
        [Ceph-noarch]
		name=Ceph noarch
		baseurl=https://download.ceph.com/rpm-15.2.8/el8/noarch
		enabled=1
		gpgcheck=1
		gpgkey=https://download.ceph.com/keys/release.asc

		[Ceph-source]
		name=Ceph SRPMS
		baseurl=https://download.ceph.com/rpm-15.2.8/el8/SRPMS
		enabled=1
		gpgcheck=1
		gpgkey=https://download.ceph.com/keys/release.asc
		```	
	2. ceph-common 패키지를 위해 epel-release 설치
        ```shell
        $ yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        ```
    3. `yum install -y --downloadonly`, `yum reinstall -y --downloadonly`를 통해 필수패키지와 의존성 패키지들을 다운로드
        - `yum install -y --downloadonly` 명령은 해당 package와 의존성이 있는 package들을 설치하지 않고 모두 다운로드 하는 명령입니다. 단, 이미 해당 패키지가 컴퓨터에 설치되어 있을 경우 패키지를 다운받지 않습니다. 따라서 그 경우에는 `yum reinstall -y --downloadonly` 명령을 통해 패키지를 다운받아야 합니다.
            ```shell
            # yum install -y --downloadonly --downloaddir={폴더} {패키지}
            # yum reinstall -y --downloadonly --downloaddir={폴더} {패키지}
            $ yum install -y --downloadonly  -downloaddir=chrony chrony
            # 이미 chrony 패키지가 설치되어 있기 때문에 패키지 다운 실패
            Package chrony-3.5-1.el8.x86_64 is already installed.
            ...
            # yum reinstall -y --downloadonly 를 통해 package 다운
            $ yum reinstall -y --downloadonly --downloaddir=chrony chrony
            ```
        - 패키지 다운로드
            ```shell
            # package들 보관할 폴더 생성
            $ mkdir -p chrony
            $ mkdir -p lvm2
            $ mkdir -p podman
            $ mkdir -p ceph-common
            # yum install -y --downloadonly 를 통해 패키지 및 의존성 패키지들 다운로드
            # 이미 패키지가 존재하여 다운로드가 실패하실 경우
            # yum reinstall -y --downloadonly 을 통해 패키지를 다운로드 하시기 바랍니다.
            
            # yum install -y --downloadonly --downloaddir={폴더} {패키지}
            # yum reinstall -y --downloadonly --downloaddir={폴더} {패키지}
            $ yum install -y --downloadonly --downloaddir=chrony chrony
            $ yum install -y --downloadonly --downloaddir=lvm2 lvm2
            $ yum install -y --downloadonly --downloaddir=podman podman
            $ yum install -y --downloadonly --downloaddir=ceph-common ceph-common

            # package 다운 확인 예시
            $ ls ceph-common
            ceph-common-15.2.8-0.el8.x86_64.rpm   libcephfs2-15.2.8-0.el8.x86_64.rpm        librbd1-15.2.8-0.el8.x86_64.rpm     platform-python-pip-9.0.3-18.el8.noarch.rpm         python3-prettytable-0.7.2-14.el8.noarch.rpm  python36-3.6.8-2.module_el8.3.0+562+e162826a.x86_64.rpm
            ...
            ```
    ### 패키지 설치 방법
    1. 다운 받은 필수 패키지 및 의존성 패키지들을 폐쇄망 환경에 다음 명령을 통해 설치합니다.
        ```shell
        # ex) ceph-common package 설치
        $ cd ceph-common
        $ yum install -y *.rpm
        # 확인
        $ ceph -v
        ceph version 15.2.8 (bdf3eebcd22d7d0b3dd4d5501bee5bac354d5b55) octopus (stable)
        ```

## 필수 컨테이너 이미지
- ceph v15.2.8을 배포하는데 필요한 container image는 다음과 같습니다.
    - docker.io/ceph/ceph:v15.2.8
    - docker.io/ceph/ceph-grafana:6.6.2
    - docker.io/prom/prometheus:v2.18.1
    - docker.io/prom/alertmanager:v0.20.0
    - docker.io/prom/node-exporter:v0.18.1
    ### 이미지 다운로드 방법
    1. 인터넷이 되는 환경에서 `podman` 또는 `docker` 을 이용하여 이미지를 다운받고, tar 형태로 저장합니다.
        ```shell
        # podman 또는 docker을 통해 이미지들 pull
        # podman pull {image} or docker pull {image}
        $ podman pull docker.io/ceph/ceph:v15.2.8
        $ podman pull docker.io/ceph/ceph-grafana:6.6.2
        $ podman pull docker.io/prom/prometheus:v2.18.1
        $ podman pull docker.io/prom/alertmanager:v0.20.0
        $ podman pull docker.io/prom/node-exporter:v0.18.1

        # podman 또는 docker를 통해 이미지들 tar 파일로 저장
        # podman save -o {tar} {iamge} or docker save -o {tar} {iamge}
        $ podman save -o ceph.tar docker.io/ceph/ceph:v15.2.8
        $ podman save -o ceph-grafana.tar docker.io/ceph/ceph-grafana:6.6.2
        $ podman save -o prometheus.tar docker.io/prom/prometheus:v2.18.1
        $ podman save -o alertmanager.tar docker.io/prom/alertmanager:v0.20.0
        $ podman save -o node-exporter.tar docker.io/prom/node-exporter:v0.18.1
        ```

    ### 폐쇄망 환경의 registry에 이미지 업로드 방법
    > 폐쇄망 환경에 이미 private registry가 동작하고 있다고 가정합니다. ex) registry 주소: 192.168.70.100:5000
    - private reistry 구성 방법 : https://github.com/tmax-cloud/install-registry/blob/5.0/podman.md
    1. private registry가 인증 없이 http를 사용할 경우, 모든 노드에서 `/etc/containers/registries.conf`의 `[registries.insecure]` 항목에 private registry를 추가합니다.
        ```shell
        #/etc/containers/registries.conf
        ...
        [registries.insecure]
        registries = ['192.168.70.100:5000'] # registry 주소 추가
        ```
    2. 한 노드에서 다음 명령들을 통해 tar파일 형태의 이미지를 registry에 업로드합니다.
        ```shell
        # podman load를 통해 tar파일의 이미지를 노드에 load
        # podman load -i {tar}
        $ podman load -i ceph.tar
        $ podman load -i ceph-grafana.tar
        $ podman load -i prometheus.tar
        $ podman load -i alertmanager.tar
        $ podman load -i node-exporter.tar

        # registry에 push 하기 위해 image들에 tag 설정
        # podman tag {docker.io/iamge_name} {private_registry/image_name}
        $ podman tag docker.io/ceph/ceph:v15.2.8 192.168.70.100:5000/ceph/ceph:v15.2.8
        $ podman tag docker.io/ceph/ceph-grafana:6.6.2 192.168.70.100:5000/ceph/ceph-grafana:6.6.2
        $ podman tag docker.io/prom/prometheus:v2.18.1 192.168.70.100:5000/prom/prometheus:v2.18.1
        $ podman tag docker.io/prom/node-exporter:v0.18.1 192.168.70.100:5000/prom/node-exporter:v0.18.1
        $ podman tag docker.io/prom/alertmanager:v0.20.0 192.168.70.100:5000/prom/alertmanager:v0.20.0

        # tag 설정한 image들을 registry에 push
        # podman {private_registry/image_name}
        $ podman push 192.168.70.100:5000/ceph/ceph:v15.2.8
        $ podman push 192.168.70.100:5000/ceph/ceph-grafana:6.6.2
        $ podman push 192.168.70.100:5000/prom/prometheus:v2.18.1
        $ podman push 192.168.70.100:5000/prom/alertmanager:v0.20.0
        $ podman push 192.168.70.100:5000/prom/node-exporter:v0.18.1

        ```
## ceph 설치
- ceph를 설치하기 위해서는 `cephadm` binary가 필요합니다.
1. 인터넷이 되는 환경에서 15.2.8 버전 `cephadm` binary를 다운로드합니다.
	```shell
	$ curl --silent --remote-name --location https://github.com/ceph/ceph/raw/v15.2.8/src/cephadm/cephadm
	$ chmod +x cephadm
	```
2. 설치 전 ceph를 설치할 노드들에 hostname 설정이 되어 있어야합니다. 제대로 되어 있지 않으면 설치가 실패합니다.
    ```shell
    $ hostname localhost #host 이름 localhost로 설정
    ```

3. bootstrap 명령어를 이용한 ceph 설치시 image 주소에 private registry의 image 주소를 명시합니다.
    - 해당 작업은 `ceph daemon`만을 private registry의 image로 배포하는 것이며 monitoring에 사용되는 데몬들(`ceph-grafana`, `prometheus`, `alertmanager`, `node-exporter`)의 private registry image 설정은 이후 작업들에서 수행합니다.
    ```shell
    # ./cephadm --image {ceph container image 주소} bootstrap --mon-ip {ip주소}
    
    $ ./cephadm --image 192.168.70.100:5000/ceph/ceph:v15.2.8 bootstrap --mon-ip 192.168.6.175
    ```
4. `ceph -s`, `ceph orch ls --refresh`, `ceph orch ps --refresh` 등을 통해서 ceph가 설치된 것을 확인한 후, monitoring 데몬들의 이미지 주소를 private registry image 주소로 수정합니다.
    ```shell
    # ceph orch ls --refresh 를 통해 monitoring service 배포 확인(alertmanager,grafana,node-exporter,prometheus)
    # mgr,mon,crash service는 private registry image로 배포 확인됨
    $ ceph orch ls --refresh
    NAME           RUNNING  REFRESHED  AGE  PLACEMENT  IMAGE NAME                             IMAGE ID
    alertmanager       0/1  -          -    count:1    <unknown>                              <unknown>
    crash              1/1  18s ago    46s  *          192.168.70.100:5000/ceph/ceph:v15.2.8  5553b0cb212c
    grafana            0/1  -          -    count:1    <unknown>                              <unknown>
    mgr                1/2  18s ago    47s  count:2    192.168.70.100:5000/ceph/ceph:v15.2.8  5553b0cb212c
    mon                1/5  18s ago    47s  count:5    192.168.70.100:5000/ceph/ceph:v15.2.8  5553b0cb212c
    node-exporter      0/1  18s ago    39s  *          docker.io/prom/node-exporter:v0.18.1   <unknown>
    prometheus         0/1  -          -    count:1    <unknown>                              <unknown>

    # monitoring service들 이미지를 private registry image로 수정
    # ceph config set mgr mgr/cephadm/container_image_{daemon} {private_registry}/{image}
    $ ceph config set mgr mgr/cephadm/container_image_prometheus 192.168.70.100:5000/prom/prometheus:v2.18.1
    $ ceph config set mgr mgr/cephadm/container_image_node_exporter 192.168.70.100:5000/prom/node-exporter:v0.18.1
    $ ceph config set mgr mgr/cephadm/container_image_alertmanager 192.168.70.100:5000/prom/alertmanager:v0.20.0
    $ ceph config set mgr mgr/cephadm/container_image_grafana 192.168.70.100:5000/ceph/ceph-grafana:6.6.2

    # monitoring service 들 재배포
    # ceph orch redeploy {service}
    $ ceph orch redeploy alertmanager
    $ ceph orch redeploy grafana
    $ ceph orch redeploy prometheus
    $ ceph orch redeploy node-exporter
    ```

5. `ceph orch ls --refresh`, `ceph orch ps --refresh`를 통해서 데몬들이 private registry image로 생성되었는지 확인
    ```shell
    $ ceph orch ls --refresh
    NAME           RUNNING  REFRESHED  AGE  PLACEMENT  IMAGE NAME                                      IMAGE ID
    alertmanager       1/1  2s ago     16m  count:1    192.168.70.100:5000/prom/alertmanager:v0.20.0   0881eb8f169f
    crash              1/1  2s ago     16m  *          192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c
    grafana            1/1  2s ago     16m  count:1    192.168.70.100:5000/ceph/ceph-grafana:6.6.2     a0dce381714a
    mgr                1/2  2s ago     16m  count:2    192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c
    mon                1/5  2s ago     16m  count:5    192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c
    node-exporter      1/1  2s ago     16m  *          192.168.70.100:5000/prom/node-exporter:v0.18.1  e5a616e4b9cf
    prometheus         1/1  2s ago     16m  count:1    192.168.70.100:5000/prom/prometheus:v2.18.1     de242295e225

    $ ceph orch ps --refresh
    NAME                   HOST     STATUS         REFRESHED  AGE  VERSION  IMAGE NAME                                      IMAGE ID      CONTAINER ID
    alertmanager.master1   master1  running (4m)   66s ago    4m   0.20.0   192.168.70.100:5000/prom/alertmanager:v0.20.0   0881eb8f169f  d052ecf0ffc2
    crash.master1          master1  running (17m)  66s ago    17m  15.2.8   192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c  1253f1d16469
    grafana.master1        master1  running (4m)   66s ago    4m   6.6.2    192.168.70.100:5000/ceph/ceph-grafana:6.6.2     a0dce381714a  8399d2759305
    mgr.master1.xnwpgm     master1  running (18m)  66s ago    18m  15.2.8   192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c  efbaaf084f99
    mon.master1            master1  running (18m)  66s ago    18m  15.2.8   192.168.70.100:5000/ceph/ceph:v15.2.8           5553b0cb212c  cd1586e387fd
    node-exporter.master1  master1  running (74s)  66s ago    17m  0.18.1   192.168.70.100:5000/prom/node-exporter:v0.18.1  e5a616e4b9cf  eccd0f3f92ee
    prometheus.master1     master1  running (4m)   66s ago    5m   2.18.1   192.168.70.100:5000/prom/prometheus:v2.18.1     de242295e225  6d39fb48d797
    ```
---
## [이후 과정은 기존 ceph 설치 과정과 동일합니다](https://github.com/tmax-cloud/hypersds-wiki/tree/main/prolinux_ceph_install_guide#ceph-추가설정)
