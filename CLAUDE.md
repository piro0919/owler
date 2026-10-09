# Owler

開発者向けの設計メモ。

launchd で回している定期実行を一覧にし、その回の中身を Cursor（または VS Code）の Claude Code で調べるための Mac アプリ。
Claude Code のデスクトップアプリにもローカルの定期実行はあるが、デスクトップアプリを使わずエディタで完結させたい、
というのが作った理由。需要は問わない。
窓の手本は Vercel のデプロイ一覧。最初は LaunchControl を手本にしたが、表を詰め込む業務アプリの見た目で
「ダサい」「情報過多」と言われ、見出し・灰色の1行・枠に入った実行の表だけに絞った。足すときは慎重に。

## 仕組み

- ジョブの定義は `~/Library/Application Support/Owler/jobs/<id>.json`。plist はそこから Owler が書く
- launchd のラベルは `io.kkweb.owler.job.<id>`。これで始まるものだけを Owler のジョブとみなす
- plist はコマンドを直接呼ばず、`Owler run <id>` を呼ぶ。Owler が開始・終了・終了コードを
  `runs/<id>/<stamp>.json` に、出力を同じ名前の `.log` に残してからコマンドを動かす
- 実行の間に、作業フォルダで作られた Claude Code のセッション（`~/.claude/projects/<フォルダ名>/*.jsonl`）を
  その回に紐づける。窓には最後の Claude の発言を「Claude の報告」として出す
  - 置き場の名前は実体のパスの英数字以外を `-` にしたもの。`/tmp` は `/private/tmp` になる。
    Foundation の resolvingSymlinksInPath は逆に `/private` を剥がすので realpath を使う
  - スクリプトの中で別のフォルダへ移ってから claude を呼ぶと見つからない
- ジョブのコマンドは Process ではなく posix_spawn で起こし、責任の切り離し（`responsibility_spawnattrs_setdisclaim`）を付ける。
  Owler はエディタの窓を前に出すためにアクセシビリティの許可を持つ。Process で起こすと子がその許可を引き継ぎ、
  ジョブのスクリプトがほかのアプリの画面を操作できた（2026-10-09 に実測。launchd 直では false、Owler 経由では true）。
  切り離しは公開されていない関数なので dlsym で引き、引けなければジョブを起こさない（`Spawn`）
- ジョブを足すのは Claude Code。窓の「新しい定期実行」は、相談の一言を入れた新しい会話をエディタで開くだけで、
  決まったら Claude が `Owler add` を呼ぶ。使い方は `Owler help`
- 既存の launchd のジョブは `Owler import` で取り込む。新しいほうを入れてから古いほうを外し、元の plist は
  `imported/` に移す。元の StandardOutPath には取り込んだあとも出力を足し続ける（`alsoLogTo`）

## メニューバー

窓が本体で、メニューバーは入口。各ジョブの前回の成否を並べ、押すと窓でそのジョブを開く。アイコンの横には、
前回が失敗のジョブの数を「!」の印つきで、実行中のジョブの数を回る輪つきで出す。両方あれば上下2段で、失敗が上。
描き方は Hawky の StatusTitle を写した（影絵ごと1枚の絵にしてテンプレート画像にする。輪は 15 fps、
「視差効果を減らす」のときは止める）。設定の「メニューバーに表示」で出し入れでき、既定は出す。
出しているあいだは、窓を閉じてもアプリは終わらない。

常駐アイコンが埋まっていると macOS はアイコンを画面外へ追いやる。AX で取れる座標が `x = -9019` のように
なっていたら、それ（Hawky と同じ落とし穴）。メニューの中身は AX で `AXPress` すれば開いて読める。

## エディタで開く

拡張は `cursor://anthropic.claude-code/open?session=…&prompt=…` を受け付ける（`vscode://` も同じ）。
prompt は送られず入力欄に入るだけ。

- **`claude -p` のセッションは session で開けない。** 拡張は記録の `entrypoint` が `sdk-cli` / `sdk-ts` / `sdk-py`
  のセッションを一覧から外していて（拡張の `Rv` 関数）、渡しても空の新しい会話になる。なので session は使わず、
  記録と出力の置き場を一言目に入れて新しい会話を開く
- URL は前面の窓で開かれる。フォルダを開いた直後に渡すと、まだ前にある別の窓に入る。
  アクセシビリティの API で、窓名がそのフォルダのものになったのを確かめてから渡す（`Focus.bringForward`）。
  窓名の規則と macOS のタブで束ねた窓の押し方は Hawky と同じ
- 初回は Cursor が「拡張機能がこの URI を開くことを許可しますか？」を出す。押すのは利用者

## 手元で動かす

```sh
./build.sh
./Owler.app/Contents/MacOS/Owler --selftest
open ./Owler.app
```

plist には、登録したときの Owler の実行ファイルのパスが入る。手元の Mac では 2026-10-09 から Homebrew で入れた
`/Applications/Owler.app` を使っていて、ジョブもそこを呼ぶ。置き場所を変えたら、各ジョブを `Owler add` か `import` で入れ直す。

**Gatekeeper に通すまでは、launchd からの起動も黙って殺される。** 自己署名なので、ダウンロードした版は
「プライバシーとセキュリティ」の「このまま開く」を押すまで、窓の起動もコマンドとしての起動も止められる。
コマンドは終了コード 137（SIGKILL）で何も出さずに終わり、`/usr/bin/log` には AppleSystemPolicy の
「Security policy would not allow process」が残る。押したあとは launchd からの起動も通る（実測）。
手元の版を上げるときは Homebrew で入れ直さず、Owler 自身の更新（Sparkle）で上げる。Homebrew で入れ直すと印
（com.apple.quarantine）が付き直し、押し直すまでジョブが黙って止まる恐れがある。Sparkle で上げた版には付かない
（0.1.1 → 0.1.2 で実測）。

## リリース

Hawky と同じ。`./release.sh <版>` でビルド・`--selftest`・DMG・更新用の zip・署名した `appcast.xml` を作り、
GitHub Releases に上げる。リリースノートは CHANGELOG.md のその版の節から取る。Sparkle の鍵は兄弟分と共有で、
秘密鍵はログインキーチェーンにある。署名は自己署名の「Okigae Dev」。

## まだやっていないこと

- `owler` をシェルから短い名前で呼べるようにすること

## アイコン

`assets/icon-source.png` が原画。ChatGPT で作った、四隅まで塗り切った正方形で、依頼文は `docs/art-prompt.md`。
`python3 Tools/make-icon.py` で角丸と余白を付け、`Resources/` に `.icns` とメニューバーの影絵を書き出す。
影絵は赤・緑・青の最小値で切り分ける。藍色の地と琥珀色の目が抜けて、目に穴の開いたフクロウになる。
