# QIDI Studio SMB 저장 지연 개선 포크

숨겨진 홈 화면이 3MF 저장 때마다 최근 프로젝트 전체의 파일 시각을 조회하던 경로를 보류·병합하는 소스 패치입니다. Bambu 수정과 같은 원인을 QIDI `02.07.02.73`에서 확인하고 필요한 부분만 옮겼습니다.

- [제품 패치](https://github.com/mk0000001/QIDIStudio/tree/fix/smb-save-recent-refresh)
- [Windows/Linux 회귀 테스트와 앱 빌드 사전 검사](https://github.com/mk0000001/QIDIStudio/actions/runs/41508902641)
- [원인·측정·검증 결과와 제한](docs/superpowers/investigations/2026-11-03-qidi-smb-validation.md)
- [설계](docs/superpowers/specs/2026-11-03-qidi-smb-save.md) · [계획](docs/superpowers/plans/2026-11-03-qidi-smb-save.md)

Windows와 Linux에서 6개 테스트/21개 assertion이 통과했고 독립 코드 검토에서 중요한 결함이 발견되지 않았습니다. 현재 QIDI 최근 기록 124개를 읽는 별도 네이티브 측정에서 기존 두 번 조회는 248회/약 2.26초였고 숨긴 상태의 패치 정책은 조회 0회였습니다. 실제 앱 저장 시간 측정은 아닙니다.

**실행 가능한 수정 앱은 아직 없습니다.** 공식 공개 소스에 `UserPresetSyncManager.cpp/.hpp`와 `pgLibConnect` import library 등 앱 빌드 필수 파일이 없어 Windows 사전 검사가 실패했습니다. 전체 앱 컴파일·GUI 저장/재열기 검증과 시험용 실행 파일 배포는 해당 소스/SDK 또는 유지관리자 빌드가 필요합니다. Actions의 Windows diagnostics는 회귀 테스트/측정 프로그램이며 QIDI Studio 앱이 아닙니다.

저장창 자체의 긴 멈춤은 별도 미해결 항목입니다. 패치는 숨겨진 홈의 불필요한 조회를 줄이며, 홈에 돌아올 때의 조회와 3MF 쓰기는 여전히 동기 처리합니다.
