# Youthcon21 실습을 위한 가상머신 환경
## 구성 및 사양
- master 1노드(2core/2GB) + worker 2노드(1core/2.5GB) 의 kubernetes v1.21.7 클러스터
- 16GB 이상의 RAM을 가진 실습 환경 권장
- worker 노드 중 1노드에는 SATA 스토리지가 추가됨
- OpenEBS 기반 볼륨 동적 프로비저닝을 사용하며 MetalLB 베어메탈 로드밸런서를 사용함

## 사전 준비
- VirtualBox 설치: https://www.virtualbox.org/wiki/Downloads
- Vagrant 설치: https://www.vagrantup.com/downloads

## 가상 머신 초기 구성
- 이 리포지토리를 clone한 후 `vagrant up` 실행
- 쿠버네티스 환경이 자동 구성되며, 마스터 노드에 `127.0.0.1:60010` 으로 접속할 수 있게 됨
- 접속 정보는 `ID: vagrant, PW: vagrant` 쉘 접속 후 `su - root`로 루트 계정을 통해 아래의 작업이 이루어짐

## 실습에 사용할 프로젝트
- 배포용 웹프로젝트: https://github.com/sang5c/demo-youthcon-21-hello
- 배포용 쿠버네티스 스펙: https://github.com/sang5c/demo-youthcon-21-config

## 가상 머신 스토리지 구성
- 클라우드 기반 환경이 아니므로 볼륨을 호스트 경로를 쓰면 불편하기 때문에 스토리지 드라이버와 동적 프로비저너를 직접 구성함
- `kubectl apply -f https://openebs.github.io/charts/cstor-operator.yaml` 을 통해 openebs-cstor를 설치
- `kubectl get pods -n openebs` 명령어로 OpenEBS가 잘 구성되었는지 수시로 확인
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
- 모든 것이 잘 설치되고 나면 설치된 구성요소는 다음과 같다
``` bash
[root@m-k8s-y k8s-init]# kubectl get pods -n openebs
NAME                                              READY   STATUS    RESTARTS   AGE
cspc-operator-7c645f96d9-45jjm                    1/1     Running   0          3m7s
cstor-disk-pool-tggc-bc7d96b5d-4lbsq              3/3     Running   0          71s
cvc-operator-6b7d6dcbc5-84nt5                     1/1     Running   0          3m7s
openebs-cstor-admission-server-6ff6948d9b-9brpn   1/1     Running   0          3m7s
openebs-cstor-csi-controller-0                    6/6     Running   0          3m7s
openebs-cstor-csi-node-5xxrc                      2/2     Running   0          3m7s
openebs-cstor-csi-node-zqjcp                      2/2     Running   0          3m7s
openebs-ndm-bbbw5                                 1/1     Running   0          3m7s
openebs-ndm-c72w9                                 1/1     Running   0          3m7s
openebs-ndm-cluster-exporter-77dcf59f67-t4l5c     1/1     Running   0          3m7s
openebs-ndm-node-exporter-gsmgq                   1/1     Running   0          3m6s
openebs-ndm-node-exporter-njgfn                   1/1     Running   0          3m6s
openebs-ndm-operator-74d8c6cdf6-hxvsf             1/1     Running   0          3m7s
[root@m-k8s-y k8s-init]# kubectl get sc
NAME                       PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
cstor-csi-disk (default)   cstor.csi.openebs.io   Delete          Immediate           true                   103s
```

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
- MetalLB가 정상적으로 구성되었다면 아래와 같다
``` bash
[root@m-k8s-y k8s-init]# kubectl get pods -n metallb-system
NAME                          READY   STATUS    RESTARTS   AGE
controller-7dcc8764f4-hmdjj   1/1     Running   0          32s
speaker-8hhj2                 1/1     Running   0          32s
speaker-tt7br                 1/1     Running   0          32s
speaker-wx4nt                 1/1     Running   0          32s
```
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
- wordpress가 EXTERNAL-IP `192.168.56.240` 을 통해 노출된 것을 확인 가능
- 웹브라우저를 띄우고 http://192.168.56.240 을 접속하여 워드프레스 정상 구동 확인

## gitOps 도구 ArgoCD 설치
- ArgoCD 는 git과 kubernetes manifest를 연계하여 gitOps를 실현해주는 배포 도구이다.
- 전통적인 CI/CD 프로세스는 CI툴에서 소스코드 빌드 -> 빌드된 결과물을 CD툴을 통해 배포라는 프로세스를 따른다, 반면에 ArgoCD는 CD단계에서 CI와 관계 없이 git에 작성된 manifest에 집중한다. 애플리케이션의 소스 코드에서 시작한 패키지를 배포의 원천으로 하는 것이 아니라, git에 정의된 Pod, ConfigMap, Service, Secret 등을 원천으로 삼는다. 그러므로 ArgoCD를 통해 배포된 환경은 언제나 전체 환경의 일관성을 유지할 수 있다.
- 아래의 명령어를 통해 ArgoCD를 설치한다
``` bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
- 아래의 명령어를 사용하여 ArgoCD를 로드밸런서를 통해 외부에 노출하고 확인한다. ArgoCD가 `192.168.56.241`로 노출된다.
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
helm upgrade --install loki grafana/loki-stack  --set grafana.enabled=true,prometheus.enabled=true,prometheus.alertmanager.persistentVolume.enabled=false,prometheus.server.persistentVolume.enabled=false,loki.persistence.enabled=true,loki.persistence.storageClassName=cstor-csi-disk,loki.persistence.size=5Gi
```
- `kubectl expose deployment loki-grafana --type=LoadBalancer --name=loki-grafana-lb` 명령어로 grafana를 LoadBalancer로 노출시켜준다. 아래와 같이 `192.168.56.242`로 노출된 것을 확인할 수 있다. grafana의 Web UI는 3000번 포트로 접속한다.
``` bash
[root@m-k8s-y ~]# kubectl expose deployment loki-grafana --type=LoadBalancer --name=loki-grafana-lb
service/loki-grafana-lb exposed
[root@m-k8s-y ~]# kubectl get svc
NAME                            TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                       AGE
kubernetes                      ClusterIP      10.96.0.1        <none>           443/TCP                       41m
loki                            ClusterIP      10.97.8.135      <none>           3100/TCP                      11m
loki-grafana                    ClusterIP      10.105.119.124   <none>           80/TCP                        11m
loki-grafana-lb                 LoadBalancer   10.98.131.176    192.168.56.242   80:32100/TCP,3000:31135/TCP   45s
loki-headless                   ClusterIP      None             <none>           3100/TCP                      11m
loki-kube-state-metrics         ClusterIP      10.96.88.18      <none>           8080/TCP                      11m
loki-prometheus-alertmanager    ClusterIP      10.98.153.190    <none>           80/TCP                        11m
loki-prometheus-node-exporter   ClusterIP      None             <none>           9100/TCP                      11m
loki-prometheus-pushgateway     ClusterIP      10.97.230.200    <none>           9091/TCP                      11m
loki-prometheus-server          ClusterIP      10.105.1.81      <none>           80/TCP                        11m
wordpress                       LoadBalancer   10.98.88.179     192.168.56.240   80:30879/TCP                  25m
wordpress-mysql                 ClusterIP      None             <none>           3306/TCP                      25m
```
- grafana의 기본 비밀번호는 secret에 저장되어 있다. 이 비밀번호는 `kubectl get secrets loki-grafana -o jsonpath='{.data.admin-password}'|base64 -d` 명령어로 찾을 수 있다.
``` bash
[root@m-k8s-y ~]# kubectl get secrets loki-grafana -o jsonpath='{.data.admin-password}'|base64 -d
LmsWN9fYH4sUeUHMIvF5YYJUACeHbsUZBYd61edT
```
- JSONPath는 JSON 객체를 탐색하는 표준 방식이다. 위에서 데이터를 찾아낸 Secret을 JSON으로 표현하면 다음과 같다.
``` json
[root@m-k8s-y ~]# kubectl get secrets loki-grafana -o json
{
    "apiVersion": "v1",
    "data": {
        "admin-password": "TG1zV045ZllINHNVZVVITUl2RjVZWUpVQUNlSGJzVVpCWWQ2MWVkVA==",
        "admin-user": "YWRtaW4=",
        "ldap-toml": ""
    },
    "kind": "Secret",
    "metadata": {
        "annotations": {
            "meta.helm.sh/release-name": "loki",
            "meta.helm.sh/release-namespace": "default"
        },
        "creationTimestamp": "2021-12-08T14:08:19Z",
        "labels": {
            "app.kubernetes.io/instance": "loki",
            "app.kubernetes.io/managed-by": "Helm",
            "app.kubernetes.io/name": "grafana",
            "app.kubernetes.io/version": "8.1.6",
            "helm.sh/chart": "grafana-6.16.12"
        },
        "name": "loki-grafana",
        "namespace": "default",
        "resourceVersion": "4675",
        "uid": "02c11cf1-09e9-42e3-91b2-2b81b988f5c9"
    },
    "type": "Opaque"
}

```
- 찾아야 할 패스워드는 data > admin-password이다. JSONPath는 탐색 표현식을 중괄호 `{ }` 로 감싸서 사용할 수 있다. `.data.admin-password`를 통해 패스워드 값을 얻었으며, 쿠버네티스의 Secret는 base64 인코딩이 되어 있으므로 이를 디코딩하였다
- 유저명 admin과 위의 명령어로 얻어낸 패스워드 `LmsWN9fYH4sUeUHMIvF5YYJUACeHbsUZBYd61edT`을 이용하여 http://192.168.56.242:3000 에서 grafana에 접속한다.

## Kubernetes IDE Lens 설치
- Lens는 쿠버네티스의 관리를 쉽게 도와주는 데스크톱 애플리케이션이다. 서버에 접속하지 않고도 쿠버네티스의 자원 조회 및 변경, 로그 조회 등의 작업을 할 수 있게 해준다
- https://k8slens.dev/ 에서 다운 받을 수 있다.
- Lens에서 사용하기 위해서 아래의 명령어를 통해 kubernetes config를 출력하고 복사한다
``` bash
[root@m-k8s-y ~]# cat ~/.kube/config
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM1ekNDQWMrZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJeE1USXdPREV6TXpjME9Wb1hEVE14TVRJd05qRXpNemMwT1Zvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTUpWCmZlR0kwOEY2VlpJWU5PMk9IeFIxcGhHcjcrWEVSRjRhbnhTMTkwUXU5K0FVeWw5SGJaWm1QNlphMFF5QTFHSWMKOWdyRlcrSGtDbWoxaHAzNUtEWnVjUWpxbW82OERQK01OL0RiMGNpNUtxTTcwYU0rWlJxWENTdFBzaVM3a21iMgo2ZVNIRGwvY0FpdDlDNjBZMW5EU3R6WmtlOWRTYnBtQ01LdUVNREx3RFdoem53MXNaWUJTV0NVdHR0YXlXU2Q1CktFbU5sbThsZE95ZnM0RXR5K2t1WVpUUE1ubHp4d2xTc2xYeldseERTeWFzUHJaalIrWWZVTlB1eEVDMTNWcTgKOFJpZmVtNFNZZEp5ZlZneEpvcGlYTGVsZytvV1V3MHdiYW9kN3UwQVlqT0svZFdHVitnV242eFFOOFBtUmlHZgpHenJCVllLRTloOXczTXRrVHVrQ0F3RUFBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZBaFIzZFlQb3E3UEJDSFpiMy96VzdjaWc5OFJNQTBHQ1NxR1NJYjMKRFFFQkN3VUFBNElCQVFCQ3hubWR2UnpYeExOMHdqRCtybStmZGtwWmw4LzRJVUdqbTZ5SGgvVlJQSWQ0Mk9tbgoyMnFqZ3AwRTdFRStmK01TMituQlp3WjNBTXhtOVBqV29SSjhxVXI5Y3VYYWVhUVpjOEt1VlFHRWJHNlNQZmlGCmdod3JYWEl6aWdjOEVaMG5vMEdtVzRPMVFIMjRBLzRXTzUwdHd5amFpWkdRWVlYY2V3SG9QT3dhTXZJdWRodHAKOGtzaFZ2Mjg0dlJxM3JFV2pnR0hhS1RvRkttdWFveEtWem95RzhQVmhJejNtRzR0ZmltL1lmdFZFd0IvQlFUWQpNcGpSN0xZZW1udzhXbkpKcUh4Q3RFNkRWMVgzWnFSbFlWVkJrejFoN0FVdm1UMjM2elo1NTlrM0NDY3RZbTVZCjRjQmUzTVlULzI4SDM1dTlSbDREU3llc3ZpeWh4UTBHbXRSSQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    server: https://192.168.56.10:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURJVENDQWdtZ0F3SUJBZ0lJWVRhYWhnR2hIazh3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TVRFeU1EZ3hNek0zTkRsYUZ3MHlNakV5TURneE16TTNOVEZhTURReApGekFWQmdOVkJBb1REbk41YzNSbGJUcHRZWE4wWlhKek1Sa3dGd1lEVlFRREV4QnJkV0psY201bGRHVnpMV0ZrCmJXbHVNSUlCSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQVE4QU1JSUJDZ0tDQVFFQXg5L0Rhc3l0Q2ZVRmpPZ0QKSDFpQkVYWFlXZzdqSVQvOFZrd3o3dWZ5ejRqVENrQ0ZYV1NNVEFOekh4bmN3dmpsWENzVjNudmowTDVsdjBTego3aGVtYWpmMHJlWCswVzNSVDRNM1BxK2tJcjFyV1ZUZ0QwdUcyOXExempBdmZLOTZZcEY0Lzk1SS9QaFpDb2FZCnZGajBxZW1jaExOZE52Z1JOT1VGenAyZU9EOTlEU0lrODRNWG8yQWF5R1R6R01ZWkx5VDFIYUVtQlVkc283YUIKMmlrU1dwWm41TGs3MEpKdEhFc28rZEpxaXdtWjJseEJ0SE1RR3pjM05WZDl0dXBibTdHSmplV0F6eW5SWExRVwpraCsyTFR4K3ArSHpiOFJTakdDc1dtc2ZWTWRqdGp5cmR4OWQ3SFhjQ0ZBTVNRK2ZpLzRPTUlpL3d4c25pS2RlClFTQ0VZd0lEQVFBQm8xWXdWREFPQmdOVkhROEJBZjhFQkFNQ0JhQXdFd1lEVlIwbEJBd3dDZ1lJS3dZQkJRVUgKQXdJd0RBWURWUjBUQVFIL0JBSXdBREFmQmdOVkhTTUVHREFXZ0JRSVVkM1dENkt1endRaDJXOS84MXUzSW9QZgpFVEFOQmdrcWhraUc5dzBCQVFzRkFBT0NBUUVBdW02WThKd3MyanB2M3RJL2lIaWV2SkdYV2l6eVVZS3VtaWR1Cmhkb0pzUktVMUxMekxaeVBDWWsrQ0dpbDJwaUJCK0hkTStVTGVKbGdJSnZnV3pxYVAxNERudkpJazk4N2FFaGMKVlhqdk9qQnN5cWdleU9scmQ2dFJWdGpqSmlKcUxtQ29rQjRhZVVneVhNaHRtNVJhNjBwN1A5UEFvaTRLM3lWNgoyL0tNSyt5WjVzNGdic01IUXU5clpjdFJ5VXlHcGNIWlAvMG5aVE5KeVJxOThqYUkyVGRnVjVJa3NnQk4xZ2hLClk5c3JCWTBoVTY3WkhWSmxHL2l6eXNXSCtqMEJoN1dIcGx0M3c4Z29DVHc0Vkt5MzAveEI1bGRxN1JBc3VHK3YKeUdtN3lMZFMxZ2FibHJnV2xHTUFCaHJRMXpnZHYyOFFpNlpWSnBldklRb2IvaXJFNkE9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFcEFJQkFBS0NBUUVBeDkvRGFzeXRDZlVGak9nREgxaUJFWFhZV2c3aklULzhWa3d6N3VmeXo0alRDa0NGClhXU01UQU56SHhuY3d2amxYQ3NWM252ajBMNWx2MFN6N2hlbWFqZjByZVgrMFczUlQ0TTNQcStrSXIxcldWVGcKRDB1RzI5cTF6akF2Zks5NllwRjQvOTVJL1BoWkNvYVl2RmowcWVtY2hMTmROdmdSTk9VRnpwMmVPRDk5RFNJawo4NE1YbzJBYXlHVHpHTVlaTHlUMUhhRW1CVWRzbzdhQjJpa1NXcFpuNUxrNzBKSnRIRXNvK2RKcWl3bVoybHhCCnRITVFHemMzTlZkOXR1cGJtN0dKamVXQXp5blJYTFFXa2grMkxUeCtwK0h6YjhSU2pHQ3NXbXNmVk1kanRqeXIKZHg5ZDdIWGNDRkFNU1ErZmkvNE9NSWkvd3hzbmlLZGVRU0NFWXdJREFRQUJBb0lCQVFDYm85SVBJeXlIdVdYRwpFSkVGNHF3MnhYWmd3b0Q1VGxNWGZDVmdudnZEd2I3Y2w5dUNHeDdvdmpMeC8vaVpWcWw3dVExQmYyV3FFZWszCkpLK2I4b3lpMzhuSGRIYVY3SmIxL0s2VFFNQm1VT3Y3MXd6V3ZEQmFtUmZEWkdCR0Ruc1ZzRVB4c3MxUk42NVcKZFBNUWo1Q05reDFQZEVCYzRwUzdoSytkOGJ6WC9LOU1BZW5UOUR0N0lranJUcEpYdDY1WVQ2QjFScXBGTG85SApwdll1cmU4U25VQ1BlZDFhYjNnZUM5dDlMMlJ1SXV1SytsL1VNd3drb2orRTBNOTcrZUhFNktrMjRuY1ptbnVjCmRVb0FWQ0JTWWxQRWFnM0QzTURpOGFySXpSaGxISjhnc3NiR2txSExORXNtSXFURlJocFNocTdzclNzeGNVWGcKNGZ5OGF6UnBBb0dCQVBEK05wMkxpTndKbXExa01UdmVyRXdIZGJwakZaUnRGVkxDanBZanRESm56RUcvTnU5RgorSllqK0pURVB6b0lwRUZja0Z5WEljdVFtRjcyTXdaeDJtbDlISVFuY2pyTFhyUDBBeHBsN3ZWWlRVNlFzMHJYCi9aTUswWjRqSER5WFpjTU9VVVFLMm5QWDVKNTZWZzdwVldHMnlJaDV6andaeGkrZHVoZFRYdE5OQW9HQkFOUlMKRFk1RTZ2WDR3eC9oY1d4N1VZSDlhV2huTlM4cUN0SVczQ0puSkdzcUxIVnptTGZNdk0rZm03d2hGLy9sN2NScAo5bEcrK0dmNzBxQzY4ZEczUWdmSlF2em5ua0kvUjQ5SklraEVpZ3FNLyswNzJRWDZWeHJ0QUdHcndPbGhZWllUCko2REloSjdPUGhaanc4NzVGcDZ2aEI4V1ZiOE1EbnlucEtDRGozNXZBb0dBQTJFZE5QSmE5Zkx3aDFQcldOS1QKaWZGazFqdERkelJjWXkrMVBpZThCQ1R1ZVZHTUhLalhob3QwbGVsMmxZSy9ndWNnWXh2L2JsSlZ3S2NsS2diNApzQmdBQ1Y1Z1BMRFRZQ1NnMG9MeGFlRlpzeXRXU0V0bEUrWEg4TGEvVTU0djRCOVlSbUw4a3psSXpHd2N2dExJCnpyajRjT2w4V2QxbXFRNUdLTU9UaGRVQ2dZRUFxejlmRlorNmp4Zk1jWnRJKzRGZlZXUUtMNTRHeEhxNWJZZm8KbDRydlVjd2JQY1ExcWhGbFBHVDBuRUZvOVFvRHcwYmYyRUVhWSt3MWoxUVpGTmdsVnRoYXdsY2lTeloweGpucgpmN1JnVG5BNVA2UGt3RENSTHZOM09rL29jWlFNdkpuSWZhTWRiR1RXcVFKZ2ZVQmtvU3JaZXFWdUZZQm84dHZZCktXclRRdHNDZ1lBNTFoWEVpUGdmMms0dVpPUUdQQVpvMG1HYU1nV1p2NDRNNENKTS9yRDhSUlBEcHVzQ21LdnoKZEF3d3NONHk0azBTZlNEUHdFZ1V0Q0tReThVTWdaZ20xN1JlWHBoclg1cFRNNkp6eDNWWE1aNU1wYVE1L2VvaQpkdDg4VTVyYXI5NE5wUnNBTml6dkdZdUcveTM0REN3bmZ3Wkg0dlR1L3RJQklocnJVRUtHUkE9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQo=

```
- 해당 내용을 Lens의 File > Add Cluster에 복사한다.

#### 이 실습은 프로젝트 멘토가 집필한 `컨테이너 인프라 환경 구축을 위한 쿠버네티스/도커` (http://www.yes24.com/Product/Goods/102099414) 의 실습 자료를 기초로 진행되었습니다.
