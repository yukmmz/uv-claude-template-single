## Python Design & SOLID Principles

Pythonコードを生成・修正する際は、以下のSOLID原則を厳格に適用してください。

### 1. Single Responsibility Principle (SRP) - 単一責任の原則
- 1つのクラスや関数は、1つの目的のみを持つこと。
- ロジックとI/O（DB操作、API呼出）を分離する。

### 2. Open/Closed Principle (OCP) - 開放閉鎖の原則
- 既存のコードを修正せずに機能を拡張できるようにする。
- 拡張ポイントには抽象クラス（`abc.ABC`）や継承を活用する。

### 3. Liskov Substitution Principle (LSP) - リスコフの置換原則
- 派生クラスは、その基底クラスと置換可能でなければならない。
- 子クラスで親クラスの期待される振る舞い（戻り値の型や例外）を破壊しない。

### 4. Interface Segregation Principle (ISP) - インターフェース分離の原則
- Pythonでは `typing.Protocol` を活用し、クライアントが必要としないメソッドへの依存を強制しない「軽量なインターフェース」を定義する。

### 5. Dependency Inversion Principle (DIP) - 依存性逆転の原則
- 高レベルのモジュールは低レベルのモジュールに依存してはならない。共に「抽象」に依存すること。
- 具象クラスを直接インスタンス化せず、型ヒントには抽象型を使用し、DI（依存性の注入）を検討する。

## Python特有の補足
- 型ヒント (`typing`) をフル活用すること。
- インターフェース定義には `abc.abstractmethod` または `typing.Protocol` を使用する。

## Package Structure
- Pythonのパッケージング・ベストプラクティスに従う。
- `src` 自体をパッケージ名にしない。
- 常に `src/` の下のサブディレクトリをルートパッケージとして扱うこと。
