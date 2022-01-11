# SAN 장비 및 SAN Switch 사용 가이드

본 가이드는 SAN, SAN Switch를 사용하는데에 필요한 기본적인 사항을 기술함

# SAN 장비

LUN 생성 전 SAN의 기본 정보 확인(변경할 필요 없음)
```
>storage disk show    // 장비의 disk 구성
                     Usable           Disk    Container   Container
Disk                   Size Shelf Bay Type    Type        Name      Owner
---------------- ---------- ----- --- ------- ----------- --------- --------

1.0.0               894.0GB     0   0 SSD     aggregate   aggr2_ssd_n1
1.0.1               894.0GB     0   1 SSD     aggregate   aggr2_ssd_n1
1.0.2                1.09TB     0   2 SAS     shared      aggr0_02, aggr1_sas_n1

>aggr show            // disk의 묶음
Aggregate     Size Available Used% State   #Vols  Nodes            RAID Status
--------- -------- --------- ----- ------- ------ ---------------- ------------
aggr1_sas_n1
           16.27TB    5.17TB   68% online      11 01          raid_dp
aggr2_ssd_n1
            2.36TB    2.36TB    0% online       0 01          raid4

>vserver show         
                               Admin      Operational Root
Vserver     Type    Subtype    State      State       Volume     Aggregate
----------- ------- ---------- ---------- ----------- ---------- ----------
svm1_san    data    default    running    running     svm1_root  aggr1_sas_n1
svm2_nas    data    default    running    running     svm2_root  aggr1_sas_n1
```

1. LUN 생성
```
>lun create -vserver svm1_san -path /vol/linux/{lun_path} -size {size} -ostype linux
>lun show -vserver svm1_san   // 생성한 lun 확인
```

2. igroup 생성(노드당 1개의 igroup, 이미 생성되어 있고 노드 추가시 생성 필요함)
```
>lun igroup create -vserver svm1_san -igroup {igroup_name} -protocol fcp -ostype linux -initiator {xx:...}
>lun igroup show
```

3. lun과 igroup의 mapping 생성
```
>lun mapping create -vserver svm1_san -path /vol/linux/{lun_path} -igroup {igroup_name}
>lun show -m
```




# SAN Switch 장비
기본적인 설정은 모두 되어있으므로 수정할 필요는 없음

SAN Switch 기본 정보
```
# show flogi database
--------------------------------------------------------------------------------
INTERFACE        VSAN    FCID           PORT NAME               NODE NAME
--------------------------------------------------------------------------------
fc1/1            1     0x9b0000  21:00:f4:e9:d4:eb:51:86 20:00:f4:e9:d4:eb:51:86
fc1/3            1     0x9b0100  21:00:f4:e9:d4:eb:54:4a 20:00:f4:e9:d4:eb:54:4a
fc1/5            1     0x9b0400  21:00:f4:e9:d4:eb:52:c8 20:00:f4:e9:d4:eb:52:c8
fc1/7            1     0x9b0500  21:00:f4:e9:d4:eb:52:8a 20:00:f4:e9:d4:eb:52:8a
fc1/21           1     0x9b0200  50:0a:09:83:80:b4:5d:65 50:0a:09:80:80:b4:5d:65
fc1/21           1     0x9b0201  20:01:d0:39:ea:31:6b:2b 20:00:d0:39:ea:31:6b:2b
fc1/23           1     0x9b0300  50:0a:09:83:80:14:5d:56 50:0a:09:80:80:14:5d:56
fc1/23           1     0x9b0301  20:03:d0:39:ea:31:6b:2b 20:00:d0:39:ea:31:6b:2b
```

fc1/1, fc1/3, fc1/5, fc1/7은 호스트, fc1/21, fc1/23은 SAN 장비에 연결되어 있음
기본적으로 호스트와 SAN 장비 포트간의 zone을 생성해주어야함


1. fcalias 확인
편의성을 위한 alias를 
```
# show fcalias
fcalias name C1_1_P1 vsan 1
  interface fc1/1 swwn 20:00:00:3a:9c:c9:1b:c0

fcalias name C1_2_P1 vsan 1
  interface fc1/3 swwn 20:00:00:3a:9c:c9:1b:c0  
...
```
fc1/1 포트를 C1_1_P1이라는 alias로 만듬
fc1/3 포트를 C1_2_P1이라는 alias로 만듬

2. zone 확인
```
zone name C1_1_P1_STORAGE_A_0c vsan 1
  fcalias name STORAGE_A_0c vsan 1
    interface fc1/21 swwn 20:00:00:3a:9c:c9:1b:c0

  fcalias name C1_1_P1 vsan 1
    interface fc1/1 swwn 20:00:00:3a:9c:c9:1b:c0
...
```

C1_1_P1_STORAGE_A_0c 라는 zone은 fc1/1(호스트)와 fc1/21(SAN)간의 zone을 의미함
해당 zone의 member로 STOAGE_A_0c, C1_1_P1이 존재


3. zoneset 확인
```
# show zoneset
zoneset name myzoneset vsan 1
  zone name C1_1_P1_STORAGE_A_0c vsan 1
    fcalias name STORAGE_A_0c vsan 1
      interface fc1/21 swwn 20:00:00:3a:9c:c9:1b:c0

    fcalias name C1_1_P1 vsan 1
      interface fc1/1 swwn 20:00:00:3a:9c:c9:1b:c0

  zone name C1_1_P1_STORAGE_B_0c vsan 1
    fcalias name STORAGE_B_0c vsan 1
      interface fc1/23 swwn 20:00:00:3a:9c:c9:1b:c0

    fcalias name C1_1_P1 vsan 1
      interface fc1/1 swwn 20:00:00:3a:9c:c9:1b:c0
...
```
myzoneset이라는 zoneset에는 C1_1_P1_STORAGE_A_0c zone과 C1_1_P1_STORAGE_B_0c등의 zone이 존재함

4. zoneset 활성화

zoneset에 새로운 zone이 추가되었다면, 반드시 zoneset 활성화를 실행해야함
```
#zoneset activate name myzoneset vsan 1
#show zoneset active
```

# Host

1. HBA 채널 스캔
lun이 새로 추가되었다면, 해당 노드에서 수행
```
# echo 1 > /sys/class/fc_host/host{N}/issue_lip
# echo "- - -" > /sys/class/scsi_host/host{N}/scan
```


