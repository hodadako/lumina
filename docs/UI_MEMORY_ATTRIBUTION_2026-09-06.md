# 2026-09-06 UI·이미지 메모리 보유 분리 측정

## 대상과 방법

- 실제 설치본 Hikari 0.3.2 (12), `com.hodadako.Hikari.NativeLocal`, PID 76247.
  macOS 26.6.2, 같은 4K60 영상 재생 상태에서 약 04:47~04:53 KST 측정했다.
- `heap`, `vmmap`, `leaks --outputGraph`로 설정 창 열림/닫힘 snapshot을 수집하고,
  저장된 memgraph의 `--trace` 및 `--dominatorTree`로 참조 경로를 조사했다.
- 정상 닫기 버튼으로 설정 UI를 해제했으며, 제품 코드·앱 번들·설정값·영상은
  변경하지 않았다. 조사 후 원래처럼 설정 창을 다시 열었다.
- raw artifact는 `/tmp/hikari-ui-memory.VBvDjh/`에 있다. 임시 파일은 영구 보관을
  보장하지 않으며 memgraph는 비공개 로컬 진단 자료로 취급한다.

## 이미지 영역의 보유 경로

vmmap의 `CG image` 5개 영역 합계 약 40.6MiB를 각각 참조 추적했다.
아래 숫자는 이 영역들의 크기이며, 이미지 관련 모든 allocation의 총합이나
수정 뒤 반드시 반환되는 physical footprint를 뜻하지 않는다.

| CG image 영역 | 크기 | 확인한 참조 경로 |
| --- | ---: | --- |
| 0x11419c000–0x1161a0000 | 약 32MiB | NSApplication → NSDockTile → NSImageView → backing layer → CGImage → CGDataProvider |
| 0x113994000–0x113d98000 | 4112KiB | AppModel → CustomAppIconStore.cachedImage → NSBitmapImageRep → backing bytes |
| 0x118474000–0x118878000 | 4112KiB | AppModel → CustomMenuBarIconStore.cachedImage → NSBitmapImageRep → backing bytes |
| 0x1081dc000–0x108220000 | 272KiB | AppModel.normalizedMenuBarIconCache → NSImage → NSBitmapImageRep |
| 0x1084f8000–0x10853c000 | 272KiB | AppModel.normalizedMenuBarIconCache → NSImage → NSBitmapImageRep |

설정 UI를 닫은 뒤에도 동일한 40.6MiB가 남았다. 큰 32MiB 버퍼는 팝오버가 아닌
macOS의 application icon/Dock tile 경로에서 참조된다. 앱은 LSUIElement=true지만
`AppModel.applyApplicationIcon()`에서 `NSApplication.shared.applicationIconImage`
값을 설정한다. 이 API 동작이 큰 버퍼를 만드는 원인인지는 별도 A/B가 필요하며,
현재 관찰은 그 버퍼를 보유하는 경로를 확인한 것이다.

customAppIcon 및 customMenuBarIcon 원본 파일은 둘 다 1024×1024, 8 bits/sample이었다.
선택된 메뉴 스타일은 hikari지만 설정 화면의 custom preview를 읽는 경로가 있고,
CustomMenuBarIconStore는 읽은 원본 NSImage를 AppModel 수명 동안 보유한다.
현재 작은 normalized icon을 만들어도 큰 원본 캐시를 자동으로 해제하지 않는다.

## 설정 창 해제의 효과

| 항목 | 설정 열림 | 설정 닫힘 |
| --- | ---: | ---: |
| heap allocation 수 | 180,314 | 95,204 |
| heap allocated bytes | 40,301,330 | 32,324,592 |
| SettingsView hosting controller | 1 | 0 |
| MenuBarView hosting controller | 1 | 1 |
| CG image 영역 | 약 40.6MiB | 약 40.6MiB |

닫힘 snapshot에서 약 85,110 allocations / 7.61MiB의 heap 감소가 관측됐다.
전체 앱의 시간차 snapshot이므로 모든 차이를 설정 UI 단독 비용으로 확정하지는
않지만, SettingsView hosting controller 제거는 직접 확인됐다.

physical footprint는 열림 약 112MiB, 닫은 뒤 snapshot 약 114MiB, 이후 약
112MiB로 즉각적인 감소가 없었다. malloc 내부의 빈 공간과 영상 버퍼 변동 등이
있으므로 해제된 heap bytes와 운영체제에 즉시 반환되는 footprint를 구별한다.

## 닫힌 팝오버의 측정 한계

- 닫힌 상태에서도 MenuBarView의 NSHostingView 1개(객체 자체 2560 bytes),
  NSHostingController 1개(128 bytes), NSPopover 1개(192 bytes)가 남았다.
- dominator tree에서 MenuBarView NSHostingView가 독점적으로 보유하는 subtree는
  7.44KiB, NSPopover subtree는 1.00KiB로 나왔다. 이는 공유된 SwiftUI graph와
  AppModel·이미지 캐시 등을 제외한 값이므로 메뉴의 전체 메모리 비용이 아니다.
- AppModel은 AppDelegate·다른 view에서도 참조한다. 메뉴에서 AppModel로 이어지는
  참조가 있다는 이유로 앱 전체 캐시를 메뉴 비용에 포함해서는 안 된다.
- 실행본은 non-debuggable이며 heap은 일부 content 접근 제한을 경고했다.
  구조·참조 snapshot은 얻었지만 임의 객체의 해제를 실행하지 않았다.
- 따라서 "메뉴를 해제하면 정확히 몇 MiB 줄어드는가"는 아직 실측하지 않았다.
  정확한 효과는 동일 빌드 조건의 진단용 A/B에서 popover controller만 해제하고,
  공유 graph와 heap 및 footprint를 다시 비교해야 한다.

## 우선순위 결론

1. 메모리 관점의 가장 큰 확인 대상은 약 32MiB의 runtime app-icon buffer다.
   Finder custom icon은 보존하면서 runtime 표시용 이미지를 필요한 크기로
   분리하는 방안을 A/B로 검증할 가치가 있다. 32MiB 전체 절감을 확약하지 않는다.
2. 선택되지 않은 custom menu icon 원본 캐시의 필요성과 수명을 검토한다.
   설정 preview용 원본을 계속 보유하지 않아도 되는지 검증한다.
3. 설정 UI 해제는 이미 동작한다. 반복적인 UI 변경 알림 제거는 주로 CPU 대상이며,
   이것만으로 위 40.6MiB 이미지 버퍼가 제거되지는 않는다.
4. popup 해제는 별도 A/B 후보지만, 이번 결과만으로 수십 MiB의 절감을
   예상하거나 메뉴 전체 비용을 수 KiB라고 단정하지 않는다.
