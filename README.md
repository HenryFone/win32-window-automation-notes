# Win32 窗口自动化实操笔记

面向要**用脚本操作一个已经装好的 Windows 桌面程序**的场景（读界面文字、点按钮、枚举控件、观察进程）。
全部内容基于标准库（Python `ctypes` / PowerShell），不需要管理员权限、不装第三方框架。

> **关于本仓库的边界（先读）**
> 这里的代码和笔记都是**通用技术**，与任何具体软件无关。
> 不包含任何商业软件的逆向产物、内存转储、控件表、账号信息或界面截图。
> 文中的做法请只用在你**自己有权操作**的程序上。

---

## 一、先搞清楚：你要操作的是哪一类程序

Windows 桌面程序大致分三档，能用的手段完全不同：

| 程序类型 | 典型特征 | 能不能用脚本操作界面 |
| --- | --- | --- |
| 标准 Win32 / MFC | 用 Spy++ 能看到 `WTWindow`、`AfxWnd`、`Button` 这类类名 | ✅ 很顺，`GetDlgItem` 就能拿到控件 |
| 现代自绘 UI（Electron、Flutter、Qt） | 控件没有独立的原生句柄，窗口是一个大画布 | ⚠️ 要靠 UI Automation（UIA），或模拟真实鼠标坐标 |
| 带反自动化的程序 | 拒绝后台消息、焦点校验严格、检测模拟输入 | ❌ 基本没法稳定自动化 |

**第一步永远是**：先用下面的枚举脚本看一眼它的窗口和控件长什么样，再决定走哪条路。
不要凭想象直接写点击代码。

---

## 二、六个反复会用到的基本功

### 1. 按进程枚举顶层窗口

一个程序可能有好几个顶层窗口（登录窗、主窗、弹窗）。先把它们全列出来：

```powershell
# 把 <PID> 换成目标进程号
.\scripts\enum-windows.ps1 -ProcessId <PID>
```

原理：`EnumWindows` 遍历所有顶层窗口，用 `GetWindowThreadProcessId` 过滤出属于目标进程的那些。
拿到每个窗口的**句柄 (HWND)、类名、标题、位置、是否可见**。

### 2. 按控件 ID 找子控件

老式程序给每个控件分配了一个数字 ID，用 `GetDlgItem(parent, id)` 直接取。
如果不知道 ID，就用下面的枚举把整棵树打印出来：

```powershell
.\scripts\enum-windows.ps1 -ProcessId <PID> -DumpControls
```

### 3. 跨进程读控件文字 —— 不要用 GetWindowText

这是个经典坑：`GetWindowText` 对**别的进程**的控件有时拿不到文字
（它内部对跨进程做了特殊处理）。稳的做法是发消息：

```python
WM_GETTEXTLENGTH = 0x000E
WM_GETTEXT = 0x000D

n = user32.SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0)
buf = ctypes.create_unicode_buffer(n + 2)
user32.SendMessageW(hwnd, WM_GETTEXT, n + 1, buf)
text = buf.value
```

### 4. 点按钮：先试 BM_CLICK，不行就上真鼠标

```python
BM_CLICK = 0x00F5
user32.SendMessageW(button_hwnd, BM_CLICK, 0, 0)
```

如果没反应，说明这个按钮是自己绘制的（不是真 Button 控件），它只认真实鼠标事件。
这时才退化成「移动光标 + 按下抬起」：

```python
user32.SetCursorPos(cx, cy)          # cx,cy = 控件矩形的中心
user32.mouse_event(0x0002, 0, 0, 0, 0)   # LEFTDOWN
user32.mouse_event(0x0004, 0, 0, 0, 0)   # LEFTUP
```

> 有些程序只有在窗口**真的获得前台焦点**时才响应点击。
> 这时需要 `SetForegroundWindow`；如果系统拒绝（Windows 只允许前台进程抢焦点），
> 就用 `AttachThreadInput` 把自己的线程临时挂到当前前台线程上，再抢。

### 5. 推动一个"只在有焦点时才走"的倒计时

有些程序的强制阅读倒计时由 `WM_TIMER` 驱动，而它只在窗口被真实激活时才自走。
无人值守时就会永远停在起点。可以直接给它灌注定时器消息：

```python
WM_TIMER = 0x0113
user32.PostMessageW(timer_control_hwnd, WM_TIMER, 1, 0)
```

循环发几次，同时检查按钮的 `IsWindowEnabled` 是否变为可用 —— 变了就停。

### 6. 观察进程树（找出它偷偷调用了谁）

程序报"读不到硬件信息"这类故障时，最快的排查方法是**看它启动了哪些子进程**：

```powershell
.\scripts\watch-process-tree.ps1 -ProcessName "YourApp" -Seconds 60
```

输出格式就是 `时间 | PID=… | PPID=… | 进程名`。
`samples/procwatch-sample.txt` 是一份真实运行的样例。
**这种日志本身不含任何隐私信息**（只有进程号、父进程号和进程名），可以放心保存分享。

---

## 三、高频错误与解法

| 现象 | 原因 | 解法 |
| --- | --- | --- |
| 控件明明存在，`GetDlgItem` 返回 0 | 控件不在那一层，要递归枚举子窗口 | 用 `EnumChildWindows` 递归找 |
| 消息发出去了但程序没反应 | 该控件只认真实输入，或需要前台焦点 | 改真实鼠标/键盘事件 + 抢焦点 |
| 文字读出来是空的 | 用了 `GetWindowText` 跨进程 | 改 `SendMessage(WM_GETTEXT)` |
| 坐标点偏了 | 高 DPI 缩放下坐标被系统缩放 | 程序启动时先调 `SetProcessDPIAware()` |
| 窗口句柄过一会儿就失效 | 程序重启后 HWND 会变 | 每次操作前按 PID/标题重新查找，别缓存句柄 |
| 自动化程序自己弹黑框 | 子进程会开控制台 | 调 `subprocess` 时传 `CREATE_NO_WINDOW` |

---

## 四、自动化之前，先问自己三个问题

1. **这个程序是我自己的 / 我有权自动化它吗？**
2. **服务条款允许吗？**
3. **我的操作会不会影响别人？**

三个都是"是"才继续。这份笔记只处理技术问题，
不提供、也不鼓励针对任何具体商业软件的破解、绕过或未授权访问。

---

## 五、环境

- Windows 10 / 11
- PowerShell 5.1+（`scripts/` 里的脚本只用系统自带 cmdlet）
- 或 Python 3.8+（只用标准库 `ctypes`）

## 许可证

MIT