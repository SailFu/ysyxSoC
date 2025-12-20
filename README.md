# ysyxSoC（Verilog 生成说明）

## 背景

`make verilog` 会通过 Chisel + CIRCT 的 `firtool` 生成 Verilog。

- CIRCT 官方发布的 `firtool-1.105.0` **仅提供 Linux x86_64（linux-x64）**预编译包。
- 在 **Linux aarch64/arm64** 上需要从源码构建 `firtool`（本仓库已做了自动化处理）。

## 一键生成

在 `ysyxSoC` 目录下执行：

```bash
make verilog
```

首次在 aarch64 上执行会自动：

- `git clone` `llvm/circt` 对应 `firtool-$(FIRTOOL_VERSION)` tag
- 初始化 `llvm` submodule
- 用 `cmake + ninja` 构建 `firtool` 与 `om-linker`
- 安装到 `patch/firtool/firtool-$(FIRTOOL_VERSION)/bin/`

后续再次执行会复用已构建的 `firtool`（不会重复构建）。

## 常见问题

### 1) 报错 “Syntax error: '(' unexpected”

这是典型的 **架构不匹配**（例如在 aarch64 上误用了 x86_64 的 `firtool`）导致的。

解决：

```bash
rm -rf patch/firtool
make verilog
```

### 2) mill 报错 “exec: java: not found”

`mill` 需要 `java` 在 PATH 中。本仓库的 `Makefile` 会尝试自动使用 `$(HOME)/java/*/bin/java`；
如果你的 JDK 不在该位置，请自行把 JDK 的 `bin/` 加入 PATH（或设置 `JAVA_HOME`）。


