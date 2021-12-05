# Youthcon21 실습을 위한 가상머신 환경

## 사전 준비
- VirtualBox 설치: https://www.virtualbox.org/wiki/Downloads
- Vagrant 설치: https://www.vagrantup.com/downloads

## 가상 머신 초기 구성
- 이 리포지토리를 clone한 후 vagrant up 실행
- 쿠버네티스 환경이 자동 구성되며, 마스터 노드에 127.0.0.1:60010 으로 접속할 수 있게 됨

## 가상 머신 스토리지 구성
- 클라우드 기반 환경이 아니므로 볼륨을 호스트 경로를 쓰면 불편하기 때문에 스토리지 드라이버와 동적 프로비저너를 직접 구성함
- `kubectl apply -f https://openebs.github.io/charts/cstor-operator.yaml` 을 통해 openebs-cstor를 설치
- cstor가 설치되고 나면 Storage Pool을 구성해야함. 아래 명령어 수행 결과의 <b>name</b>을 활용할 것임
``` bash
[root@m-k8s-y ~]# kubectl get bd -n openebs
NAME                                           NODENAME   SIZE          CLAIMSTATE   STATUS   AGE
blockdevice-75dae65d6dce81e12790ab8a2e35cf6b   s1-k8s-y   10736352768   Claimed      Active   72m
```
- `vi cstor-pool.yaml`을 수행하여 blockDeviceName에 위 명령어 수행 결과의 name을 입력함
``` yaml
[root@m-k8s-y ~]# vi cstor-pool.yaml
apiVersion: cstor.openebs.io/v1
kind: CStorPoolCluster
metadata:
 name: cstor-disk-pool
 namespace: openebs
spec:
 pools:
   - nodeSelector:
       kubernetes.io/hostname: "s1-k8s-y"
     dataRaidGroups:
       - blockDevices:
           - blockDeviceName: "blockdevice-75dae65d6dce81e12790ab8a2e35cf6b"
     poolConfig:
       dataRaidGroupType: "stripe"

```
- 저장 후 `kubectl apply -f cstor-pool.yaml`로 스토리지 풀 생성
- 스토리지 풀 생성 후 `kubectl apply -f cstor-storage-class.yaml`로 스토리지 클래스 생성, 이후 PV는 이 스토리지 클래스를 기본으로 사용함

## MySQL과 WordPress 설치를 통해 스토리지 세팅 확인
- `kubectl apply -f mysql.yaml`  으로 MySQL 배포
- `kubectl apply -f wordpress.yaml` 으로 WordPress 배포
- 을 통해 정상적으로 MySQL과 WordPress가 배포되었다면 아래와 같이 확인
``` bash
[root@m-k8s-y ~]# kubectl get pods
NAME                               READY   STATUS    RESTARTS   AGE
wordpress-7b989dbf57-k46mj         1/1     Running   0          23m
wordpress-mysql-6965fc8cc8-6mh5b   1/1     Running   0          25m
[root@m-k8s-y ~]# kubectl get svc
NAME              TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP   10.96.0.1        <none>        443/TCP        7h44m
wordpress         NodePort    10.105.190.131   <none>        80:31944/TCP   23m
wordpress-mysql   ClusterIP   None             <none>        3306/TCP       25m
```
- 현재 WordPress는 NodePort를 통해 노출하게 되어 있으므로 31944로 노출된 것을 알 수 있음(실행시마다 다를 수 있음)
- 웹브라우저를 띄우고 http://192.168.1.10:31944 를 접속하여 워드프레스 정상 구동 확인
