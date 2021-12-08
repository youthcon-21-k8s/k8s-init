# Youthcon21 실습을 위한 가상머신 환경
## 구성 및 사양
- master 1노드(2core/2GB) + worker 2노드(1core/2.5GB) 의 kubernetes v1.22.3 클러스터
- 16GB 이상의 RAM을 가진 실습 환경 권장
- worker 노드 중 1노드에는 SATA 스토리지가 추가됨
- OpenEBS 기반 볼륨 동적 프로비저닝을 사용하며 MetalLB 베어메탈 로드밸런서를 사용함

## 사전 준비
- VirtualBox 설치: https://www.virtualbox.org/wiki/Downloads
- Vagrant 설치: https://www.vagrantup.com/downloads

## 가상 머신 초기 구성
- 이 리포지토리를 clone한 후 `vagrant up` 실행
- 쿠버네티스 환경이 자동 구성되며, 마스터 노드에 `127.0.0.1:60010` 으로 접속할 수 있게 됨

## 가상 머신 스토리지 구성
- 클라우드 기반 환경이 아니므로 볼륨을 호스트 경로를 쓰면 불편하기 때문에 스토리지 드라이버와 동적 프로비저너를 직접 구성함
- `kubectl apply -f https://openebs.github.io/charts/cstor-operator.yaml` 을 통해 openebs-cstor를 설치
- cstor가 설치되고 나면 Storage Pool을 구성해야함. 아래 명령어 수행 결과의 <b>name</b>을 활용할 것임
``` bash
[root@m-k8s-y ~]# kubectl get bd -n openebs
NAME                                           NODENAME   SIZE          CLAIMSTATE   STATUS   AGE
blockdevice-75dae65d6dce81e12790ab8a2e35cf6b   s1-k8s-y   10736352768   Claimed      Active   72m
```
- `vi cstor-pool-cluster.yaml`을 수행하여 blockDeviceName에 위 명령어 수행 결과의 name을 입력함
``` yaml
[root@m-k8s-y ~]# vi cstor-pool-cluster.yaml
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
- 저장 후 `kubectl apply -f cstor-pool-cluster.yaml`로 스토리지 풀 생성
- 스토리지 풀 생성 후 `kubectl apply -f cstor-storage-class.yaml`로 스토리지 클래스 생성, 이후 PV는 이 스토리지 클래스를 기본으로 사용함
## 로드밸런서 설정
- 역시 클라우드 기반 환경이 아니므로 로드밸런서 공급자가 없으므로 설정이 필요함
- MetalLB라는 것을 사용할 것임
- 아래의 명령어를 통해서 MetalLB를 사용할 수 있도록 kube-proxy 설정을 변경
``` bash
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
```
- 아래의 명령을 통해 MetalLB를 설치
``` bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/metallb.yaml
```
- MetalLB가 설정되었다면 MetalLB의 설정을 해 주어야 함
- `kubectl apply -f metallb-config.yaml` 명령어를 통해 설정을 적용

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
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1      <none>          443/TCP        8h
wordpress         LoadBalancer   10.99.165.35   192.168.1.240   80:31040/TCP   3s
wordpress-mysql   ClusterIP      None           <none>          3306/TCP       47m
```
- wordpress가 EXTERNAL-IP `192.168.1.240` 을 통해 노출된 것을 확인 가능
- 웹브라우저를 띄우고 http://192.168.1.240 을 접속하여 워드프레스 정상 구동 확인

## gitOps 도구 ArgoCD 설치
- ArgoCD 는 git과 kubernetes manifest를 연계하여 gitOps를 실현해주는 배포 도구이다.
- 전통적인 CI/CD 프로세스는 CI툴에서 소스코드 빌드 -> 빌드된 결과물을 CD툴을 통해 배포라는 프로세스를 따른다, 반면에 ArgoCD는 CD단계에서 CI와 관계 없이 git에 작성된 manifest에 집중한다. 애플리케이션의 소스 코드에서 시작한 패키지를 배포의 원천으로 하는 것이 아니라, git에 정의된 Pod, ConfigMap, Service, Secret 등을 원천으로 삼는다. 그러므로 ArgoCD를 통해 배포된 환경은 언제나 전체 환경의 일관성을 유지할 수 있다.
- 아래의 명령어를 통해 ArgoCD를 설치한다
``` bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml
```
- 아래의 명령어를 사용하여 ArgoCD를 로드밸런서를 통해 외부에 노출하고 확인한다. ArgoCD가 `192.168.1.241`로 노출된다.
``` bash
[root@m-k8s-y ~]# kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
service/argocd-server patched
[root@m-k8s-y ~]# kubectl get svc -n argocd
NAME                    TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
argocd-dex-server       ClusterIP      10.100.144.213   <none>          5556/TCP,5557/TCP,5558/TCP   25s
argocd-metrics          ClusterIP      10.98.101.201    <none>          8082/TCP                     25s
argocd-redis            ClusterIP      10.111.69.1      <none>          6379/TCP                     25s
argocd-repo-server      ClusterIP      10.100.76.209    <none>          8081/TCP,8084/TCP            25s
argocd-server           LoadBalancer   10.107.231.222   192.168.1.241   80:31906/TCP,443:30779/TCP   25s
argocd-server-metrics   ClusterIP      10.103.0.222     <none>          8083/TCP                     25s
```

## 패키지 매니저 helm 설치
- helm 은 RHEL의 yum, 맥의 brew등과 같이 쿠버네티스에 필요한 패키지를 쉽게 설치해주는 패키지 매니저이다.
- 아래의 명령어를 통해 helm을 설치한다
``` bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```
- 아래의 명령으로 helm 설치를 확인한다
``` bash
[root@m-k8s-y ~]# helm version
version.BuildInfo{Version:"v3.7.1", GitCommit:"1d11fcb5d3f3bf00dbe6fe31b8412839a96b3dc4", GitTreeState:"clean", GoVersion:"go1.16.9"}
```

## 로그수집, 모니터링을 위한 loki-stack 설치
- loki-stack은 loki(로그수집서버), promtail(로그수집 에이전트), prometheus(모니터링 메트릭 수집 서버), grafana(대시보드) 등을 모아놓은 stack이다. loki-stack의 구성 요소를 통해 쿠버네티스 클러스터의 로그와 메트릭 데이터를 수집하고 모니터링을 설정 및 시각화할 수 있다.
- 아래의 명령어로 loki-stack을 설치한다
``` bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install loki grafana/loki-stack \
--set grafana.enabled=true,prometheus.enabled=true, \
prometheus.alertmanager.persistentVolume.enabled=false, \
prometheus.server.persistentVolume.enabled=false, \
loki.persistence.enabled=true, \
loki.persistence.storageClassName=cstor-csi-disk, \ 
loki.persistence.size=5Gi
```
