# cloud-init devbox 구성

## 파일 구조
- `cloud-init-devbox.yaml` — 시스템 레벨 설정 (패키지, SSH, 방화벽, Tailscale). VM 생성 시 user-data로 전달.
- `bootstrap-user.sh` — 유저 레벨 개발도구 설치 (uv, node, aider, eza, delta, code-server 등). **별도 git 저장소에 올려서** cloud-init이 curl로 받아오는 방식.

이렇게 나눈 이유: bootstrap-user.sh 내용을 바꿀 때마다 cloud-init 파일 자체를 다시 만들 필요가 없고, 스크립트를 로컬에서 단독으로 실행/디버깅하기 쉬움.

## 배포 전 반드시 할 일
1. `cloud-init-devbox.yaml`의 `ssh_authorized_keys`를 잘리지 않은 전체 공개키로 교체
2. `write_files`의 `source.uri`를 실제 bootstrap-user.sh를 올린 저장소 raw URL로 교체
3. `bootstrap-user.sh`를 해당 저장소에 push

## Tailscale auth key 전달 (VM 생성 시, GCE 기준)
user-data 파일에 키를 넣지 않고 별도 메타데이터 키로 분리:
```bash
gcloud compute instances create devbox \
  --metadata-from-file user-data=cloud-init-devbox.yaml \
  --metadata ts-auth-key="tskey-auth-xxxxxxxxxxxx"
```
반드시 ephemeral/1회용 key로 발급할 것. 사용 후 Tailscale 관리 콘솔에서 만료/폐기 확인.

## 배포 전 문법 검증
```bash
cloud-init schema --config-file cloud-init-devbox.yaml --annotate
```

## 배포 후 검증 (VM 부팅 후)
```bash
cloud-init status --long                 # 전체 성공/에러 여부
sudo tail -f /var/log/cloud-init-output.log   # runcmd 실시간 로그
cloud-init analyze show                  # 단계별 소요 시간, 병목 확인
cat ~/bootstrap-failures.log             # bootstrap-user.sh 내 실패한 단계 목록
```

## 검증 팁
- 실제 동작 여부는 스키마 검사로 알 수 없음. 반드시 일회용 VM에 띄워서 확인.
- `bootstrap-user.sh`는 각 설치 단계를 `step` 헬퍼로 감싸서, 하나 실패해도 나머지 단계는 계속 진행하고 실패 목록만 `~/bootstrap-failures.log`에 남김.