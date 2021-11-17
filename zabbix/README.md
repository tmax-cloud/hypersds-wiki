Zabbix 연동 가이드
================
### *본 가이드는 Zabbix server와 Ceph가 설치되어 있다는 전제 하에 작성되었습니다.*

- agent 설치 파일 리스트
	- **ceph_health_logger.sh**: logger shell script => `/usr/sbin/` 위치에 저장
	- **zabbix_template_v6.xml**: zabbix template
	- **ceph_health**: logrotate 설정파일 => `/etc/logrotate.d/` 위치에 저장
	- **ceph-health-logger.service**: systemd service 등록 파일 => `/usr/lib/systemd/system/` 위치에 저장
- zabbix port: 10051
- zabbix node 환경: CentOS 8.4.2105
	
## 1. 전달받은 template을 Zabbix에 import

## 2. Zabbix에서 host 추가 및 template 연결
- host 이름은 `ceph-<fsid>`
	- Ceph fsid는 `ceph -s` 명령어로 확인 가능

## 3. Ceph에서 zabbix 활성화 및 설정
- zabbix module 활성화
```
# ceph mgr module enable zabbix
```
- zabbix identifier, zabbix_host 설정
```
# ceph zabbix config-set zabbix_host <zabbix 서버의 IP>
# ceph zabbix config-set identifier ceph-<fsid>
```
	
## 4. Ceph mgr 컨테이너에 zabbix-sender 설치
- active mgr의 container id 확인
	- `ceph orch ps`에서 확인 가능
- active mgr container에 접속
```
# podman exec -it <container_id> /bin/bash
```
- container에 접속 후 zabbix-sender 설치
```
# yum install -y https://repo.zabbix.com/zabbix/5.0/rhel/8/x86_64/zabbix-sender-5.0.11-1.el8.x86_64.rpm
```
	
## 5. Zabbix node에서 zabbix-agent 설정
- `/etc/zabbix/zabbix_agentd.conf` 설정변경
```
ServerActive=127.0.0.1
Hostname=ceph-<fsid>
MaxLinesPerSecond=100
```
	
## 6. ceph-health-logger 서비스 실행
- systemd daemon 로드
```
# systemctl daemon-reload
```
- systemd 서비스 등록
```
# systemctl enable ceph-health-logger.service
```
- ceph-health-logger 서비스 시작
```
# systemctl start ceph-health-logger.service
```
- `/var/log/ceph_health.log` 파일에 log가 쌓이는지 확인
	
## 7. 동작 확인
- Ceph zabbix discovery & send 수행
```
# ceph zabbix discovery
# ceph zabbix send
```
- Zabbix monitoring 탭의 latest data에서 데이터가 잘 전달되는지 확인
