# Git Workflow & Commit Message Rule

## 1. 目的
.gitignore で除外されていないあらゆるファイルについて、修正を行った際に、コードの変更内容を、人間および外部AI（Gemini等）が迅速に理解できるよう、標準化された形式でコミットメッセージを生成し、 `commit_msg.md` に上書き保存することを義務付けるルール。
※AI自身がコミットを実行してはならない。あくまでメッセージの提案のみを行う。

## 2. 生成のタイミング
ファイルの作成、修正、リファクタリング、またはライブラリの追加（`uv add`）が完了した直後に、必ず「提案されるコミットメッセージ」を `commit_msg.md` に上書き保存すること。

## 3. コミットメッセージの形式
以下の Conventional Commits 形式に従うこと。

```
<type>: <description>

[Optional Body]
- 変更の要点（箇条書き）
- [ASSUMPTIONS] がある場合は、その要約をここに含める
```

### Type の定義
- **feat**: 新機能の追加、研究アルゴリズムの新規実装
- **fix**: バグ修正
- **docs**: ドキュメントのみの変更（ARCHITECTURE.md の更新など）
- **style**: コードの意味に影響を与えない変更（フォーマット、空白の修正など）
- **refactor**: バグ修正や機能追加ではないコードの変更（SOLID原則に基づく修正など）
- **test**: テストコードの追加・修正
- **chore**: ビルドプロセスや補助ツールの変更、ライブラリ追加（uv add）

## 4. 出力時の義務
メッセージを出力する際、必ず以下の形式で提示すること。
```md
feat: motor selection logic based on torque requirements

- Added MotorSelector class in src/nlinfit_flapaero/logic.py
- Implemented basic efficiency calculation
- [ASSUMPTION]: Assumed nominal voltage of 12V for all motors.
```

## 5. マルチリポジトリ環境での保存先ルール（重要）
複数の独立したGitリポジトリ（ライブラリ）が混在する構成の場合、
AIはファイル変更後、**「どのパッケージに対する変更か」を判定し、該当するリポジトリのルート階層に `commit_msg.md` を保存**しなければならない。

※ 複数のリポジトリ（例: `flapcfd_io` とルートの `scripts`）を同時に変更した場合は、**それぞれのリポジトリごとに別々の `commit_msg.md` を作成**して報告すること。