# Free Pascal / Lazarus 开发速查手册

> 本手册基于官方文档、社区经验和最佳实践整理，适用于 Free Pascal 3.2+ 和 Lazarus 2.x

---

## 目录

1. [环境配置](#1-环境配置)
2. [语言基础](#2-语言基础)
3. [常用单元和 API](#3-常用单元和-api)
4. [Lazarus IDE 快捷键](#4-lazarus-ide-快捷键)
5. [内存管理与指针](#5-内存管理与指针)
6. [异常处理](#6-异常处理)
7. [文件操作](#7-文件操作)
8. [面向对象编程](#8-面向对象编程)
9. [泛型和集合](#9-泛型和集合)
10. [多线程](#10-多线程)
11. [LCL 图形界面开发](#11-lcl-图形界面开发)
12. [调试技巧](#12-调试技巧)
13. [常见陷阱与最佳实践](#13-常见陷阱与最佳实践)
14. [性能优化](#14-性能优化)
15. [跨平台开发](#15-跨平台开发)

---

## 1. 环境配置

### 1.1 编译器开关

```pascal
{$mode objfpc}{$H+}{$J-}  // 推荐模式：ObjFPC + 长字符串 + 只读常量
{$mode delphi}            // Delphi 兼容模式
{$mode tp}                // Turbo Pascal 模式
```

常用编译器指令：
- `{$R+}` / `{$R-}` - 范围检查
- `{$Q+}` / `{$Q-}` - 溢出检查
- `{$O+}` / `{$O-}` - 优化开关
- `{$L+}` / `{$L-}` - 调试信息
- `{$B+}` / `{$B-}` - 完全布尔短路

### 1.2 项目结构

```
project/
├── src/                  # 源代码
│   ├── main.pas
│   ├── utils.pas
│   └── ...
├── res/                  # 资源文件
├── _tmp/                 # 临时文件（不提交）
│   ├── build/
│   ├── test/
│   └── logs/
├── script/               # 构建脚本
├── docs/                 # 文档
├── project.lpr           # 主程序入口
└── project.lpi           # Lazarus 项目文件
```

---

## 2. 语言基础

### 2.1 基本数据类型

| 类型 | 大小 | 范围 | 说明 |
|------|------|------|------|
| `Boolean` | 1 字节 | True/False | 布尔值 |
| `Char` | 1 字节 | ASCII 字符 | 单个字符 |
| `ShortString` | 0-255 字节 | - | 短字符串（TP 兼容） |
| `AnsiString` | 可变 | - | 8 位字符串（H+ 默认） |
| `String` | 可变 | - | Unicode 字符串（H+ 默认） |
| `Byte` | 1 字节 | 0-255 | 无符号 8 位整数 |
| `Integer` | 4 字节 | -2^31~2^31-1 | 有符号 32 位整数 |
| `Int64` | 8 字节 | -2^63~2^63-1 | 有符号 64 位整数 |
| `Single` | 4 字节 | - | 单精度浮点数 |
| `Double` | 8 字节 | - | 双精度浮点数 |
| `Pointer` | 4/8 字节 | - | 指针 |

### 2.2 变量声明与赋值

```pascal
program Example;
{$mode objfpc}{$H+}{$J-}

var
  myInt: Integer;
  myStr: String;
  myDouble: Double;

begin
  myInt := 42;              // 赋值操作符 :=
  myStr := 'Hello';
  myDouble := 3.14159;
  
  // 常量
  const
    MaxSize = 100;
    Pi = 3.1415926535;
end.
```

**重要**：
- 赋值使用 `:=`，比较使用 `=`
- 变量使用前必须初始化，否则包含垃圾值

### 2.3 控制结构

#### If-Then-Else

```pascal
if age >= 18 then
  WriteLn('Adult')
else
  WriteLn('Minor');

// 多语句块需要 begin...end
if score >= 90 then
begin
  WriteLn('Excellent');
  Grade := 'A';
end
else if score >= 80 then
  WriteLn('Good');
```

#### Case-Of

```pascal
case grade of
  'A': WriteLn('Excellent');
  'B': WriteLn('Good');
  'C', 'D': WriteLn('Passed');
  else WriteLn('Failed');
end;
```

#### For 循环

```pascal
// 递增循环
for i := 1 to 10 do
  WriteLn(i);

// 递减循环
for i := 10 downto 1 do
  WriteLn(i);

// 遍历数组/集合
for Item in MyList do
  Process(Item);
```

#### While 和 Repeat

```pascal
// While - 先检查条件
i := 1;
while i <= 10 do
begin
  WriteLn(i);
  Inc(i);  // i := i + 1
end;

// Repeat - 至少执行一次
i := 1;
repeat
  WriteLn(i);
  Inc(i);
until i > 10;
```

### 2.4 过程与函数

```pascal
// 过程（无返回值）
procedure Greet(const Name: String);
begin
  WriteLn('Hello, ', Name, '!');
end;

// 函数（有返回值）
function Add(A, B: Integer): Integer;
begin
  Result := A + B;  // 返回值赋值给 Result
end;

// 带 var 参数的过程（可修改传入变量）
procedure Swap(var A, B: Integer);
var
  Temp: Integer;
begin
  Temp := A;
  A := B;
  B := Temp;
end;

// 带 const 参数（只读，避免复制大对象）
procedure ProcessData(const Data: TStringList);
begin
  // Data 不可被修改
end;
```

---

## 3. 常用单元和 API

### 3.1 核心单元

| 单元 | 功能 |
|------|------|
| `SysUtils` | 系统工具（异常、字符串、内存管理） |
| `Classes` | 基础类（TStream, TList, TComponent） |
| `Math` | 数学函数（Power, Sin, Cos, RoundTo） |
| `StrUtils` | 字符串工具（AnsiLeftStr, AnsiReplaceStr） |
| `DateUtils` | 日期时间处理 |
| `FileUtil` | 文件操作 |
| `IniFiles` | INI 文件读写 |
| `Generics.Collections` | 泛型集合 |
| `Generics.Defaults` | 泛型比较器和哈希 |

### 3.2 常用函数

#### 字符串操作

```pascal
uses SysUtils, StrUtils;

var
  S: String;
begin
  S := 'Hello World';
  
  Length(S);              // 长度
  Copy(S, 1, 5);          // 截取 'Hello'
  Insert('Nice ', S, 6);  // 插入
  Delete(S, 1, 5);        // 删除
  Pos('World', S);        // 查找位置
  AnsiReplaceStr(S, 'World', 'Pascal');  // 替换
  UpperCase(S);           // 转大写
  LowerCase(S);           // 转小写
  Trim(S);                // 去除首尾空格
  Format('Value: %d', [100]);  // 格式化
  IntToStr(100);          // 整数转字符串
  StrToInt('100');        // 字符串转整数
  FloatToStr(3.14);       // 浮点转字符串
  StrToFloat('3.14');     // 字符串转浮点
end;
```

#### 数学函数

```pascal
uses Math;

var
  R: Double;
begin
  Abs(-5);                // 绝对值 5
  Sqr(5);                 // 平方 25
  Sqrt(16);               // 平方根 4
  Power(2, 10);           // 2^10 = 1024
  Sin(PI/2);              // 正弦 1
  Cos(0);                 // 余弦 1
  Round(3.7);             // 四舍五入 4（银行家舍入）
  Ceil(3.2);              // 向上取整 4
  Floor(3.8);             // 向下取整 3
  RoundTo(123.456, -2);   // 舍入到小数点后 2 位 123.46
  Min(5, 10);             // 最小值 5
  Max(5, 10);             // 最大值 10
end;
```

#### 数组和列表

```pascal
uses Classes, SysUtils;

var
  MyList: TStringList;
  i: Integer;
  Arr: array of Integer;
begin
  // 动态数组
  SetLength(Arr, 10);
  Arr[0] := 1;
  
  // 字符串列表
  MyList := TStringList.Create;
  try
    MyList.Add('Item1');
    MyList.Add('Item2');
    MyList.Sorted := True;
    
    for i := 0 to MyList.Count - 1 do
      WriteLn(MyList[i]);
  finally
    MyList.Free;
  end;
end;
```

---

## 4. Lazarus IDE 快捷键

### 4.1 基本编辑

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+C` | 复制 |
| `Ctrl+X` | 剪切 |
| `Ctrl+V` | 粘贴 |
| `Ctrl+Z` | 撤销 |
| `Ctrl+Y` | 重做 |
| `Ctrl+A` | 全选 |
| `Ctrl+S` | 保存 |
| `Ctrl+Shift+S` | 全部保存 |
| `Ctrl+O` | 打开文件 |
| `Ctrl+F4` | 关闭文件 |
| `Ctrl+N` | 新建窗体 |
| `Ctrl+Shift+N` | 新建单元 |

### 4.2 编译和调试

| 快捷键 | 功能 |
|--------|------|
| `F9` | 编译/运行 |
| `F2` | 停止 |
| `F8` | 单步执行（进入过程） |
| `F7` | 单步执行（进入函数） |
| `Shift+F8` | 单步执行（退出） |
| `F4` | 跳转到定义 |
| `Alt+←` | 返回上一个位置 |
| `Alt+→` | 前进 |

### 4.3 搜索和导航

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+F` | 查找 |
| `F3` | 查找下一个 |
| `Shift+F3` | 查找上一个 |
| `Ctrl+R` | 替换 |
| `Ctrl+G` | 跳转到行 |
| `F12` | 切换表单/代码 |
| `Ctrl+Shift+R` | 最近打开的文件 |

---

## 5. 内存管理与指针

### 5.1 动态内存分配

```pascal
// 指针
var
  P: ^Integer;
begin
  New(P);        // 分配内存
  P^ := 42;      // 使用
  Dispose(P);    // 释放内存
end;

// 动态数组
var
  Arr: array of Integer;
begin
  SetLength(Arr, 10);  // 分配
  Arr[0] := 1;
  // 自动释放（离开作用域时）
end;

// 字符串（引用计数，自动管理）
var
  S: String;
begin
  S := 'Hello';  // 自动分配
  // 自动释放
end;
```

### 5.2 类实例管理

```pascal
var
  Obj: TObject;
begin
  Obj := TObject.Create;
  try
    // 使用对象
  finally
    Obj.Free;  // 必须释放
  end;
end;

// 推荐：使用 try...finally 确保释放
```

### 5.3 内存泄漏检测

```pascal
// 编译时启用堆跟踪
{$M+}  // 支持 RTTI
// 运行时使用 -gh 编译选项

// 调试时检查泄漏
uses HeapTrc;  // 替换默认内存管理器
```

**最佳实践**：
1. 使用 `try...finally` 确保资源释放
2. 优先使用自动管理的类型（String, 动态数组）
3. 对象所有权要明确（谁创建，谁释放）
4. 使用 `FreeAndNil(Obj)` 代替 `Obj.Free; Obj := nil;`

---

## 6. 异常处理

### 6.1 Try-Except-Finally

```pascal
// 捕获异常
try
  Result := A div B;
except
  on E: EDivByZero do
    WriteLn('除零错误');
  on E: EConvertError do
    WriteLn('转换错误');
  on E: Exception do
    WriteLn('错误：', E.Message);
end;

// 确保资源释放（总是执行）
var
  F: TextFile;
begin
  AssignFile(F, 'test.txt');
  try
    Reset(F);
    // 读取文件
  finally
    CloseFile(F);  // 无论是否异常都会执行
  end;
end;

// 组合使用
try
  try
    // 可能抛出异常的代码
  except
    on E: Exception do
      WriteLn('捕获异常：', E.Message);
  end;
finally
  // 清理资源
end;
```

### 6.2 自定义异常

```pascal
type
  EMyException = class(Exception);
  
  EFileNotFound = class(Exception);

procedure DoSomething;
begin
  if not FileExists('test.txt') then
    raise EFileNotFound.Create('文件不存在');
end;
```

---

## 7. 文件操作

### 7.1 文本文件

```pascal
var
  F: TextFile;
  Line: String;
begin
  // 写入
  AssignFile(F, 'output.txt');
  Rewrite(F);
  try
    WriteLn(F, 'Line 1');
    WriteLn(F, 'Line 2');
  finally
    CloseFile(F);
  end;
  
  // 读取
  AssignFile(F, 'input.txt');
  Reset(F);
  try
    while not Eof(F) do
    begin
      ReadLn(F, Line);
      WriteLn(Line);
    end;
  finally
    CloseFile(F);
  end;
end;
```

### 7.2 二进制文件

```pascal
type
  TRecord = record
    ID: Integer;
    Name: String;
  end;

var
  F: File of TRecord;
  Rec: TRecord;
begin
  AssignFile(F, 'data.bin');
  Rewrite(F);
  try
    Rec.ID := 1;
    Rec.Name := 'Test';
    Write(F, Rec);
  finally
    CloseFile(F);
  end;
end;
```

### 7.3 使用 TFileStream

```pascal
uses Classes;

var
  Stream: TFileStream;
  Data: TBytes;
begin
  // 读取文件
  Stream := TFileStream.Create('file.bin', fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, Stream.Size);
    Stream.ReadBuffer(Data[0], Stream.Size);
  finally
    Stream.Free;
  end;
  
  // 写入文件
  Stream := TFileStream.Create('output.bin', fmCreate);
  try
    Stream.WriteBuffer(Data[0], Length(Data));
  finally
    Stream.Free;
  end;
end;
```

### 7.4 INI 文件

```pascal
uses IniFiles, SysUtils;

var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create('config.ini');
  try
    Ini.WriteString('General', 'Name', 'Test');
    Ini.WriteInteger('General', 'Version', 1);
    Ini.WriteBool('Settings', 'Enabled', True);
    
    // 读取
    WriteLn(Ini.ReadString('General', 'Name', ''));
    WriteLn(Ini.ReadInteger('General', 'Version', 0));
  finally
    Ini.Free;
  end;
end;
```

---

## 8. 面向对象编程

### 8.1 类定义

```pascal
type
  TPerson = class
  private
    FName: String;
    FAge: Integer;
    procedure SetName(const Value: String);
  protected
    procedure Display; virtual;
  public
    constructor Create(const AName: String; AAge: Integer);
    destructor Destroy; override;
    procedure Speak;
    property Name: String read FName write SetName;
    property Age: Integer read FAge write FAge;
  end;

constructor TPerson.Create(const AName: String; AAge: Integer);
begin
  inherited Create;
  FName := AName;
  FAge := AAge;
end;

destructor TPerson.Destroy;
begin
  // 清理资源
  inherited Destroy;
end;

procedure TPerson.SetName(const Value: String);
begin
  FName := Value;
end;

procedure TPerson.Display;
begin
  WriteLn('Name: ', FName, ', Age: ', FAge);
end;

procedure TPerson.Speak;
begin
  Display;
  WriteLn('Hello!');
end;
```

### 8.2 继承

```pascal
type
  TEmployee = class(TPerson)
  private
    FSalary: Double;
  public
    constructor Create(const AName: String; AAge: Integer; ASalary: Double);
    procedure Display; override;  // 重写父类方法
  end;

constructor TEmployee.Create(const AName: String; AAge: Integer; ASalary: Double);
begin
  inherited Create(AName, AAge);  // 调用父类构造器
  FSalary := ASalary;
end;

procedure TEmployee.Display;
begin
  inherited Display;  // 调用父类方法
  WriteLn('Salary: ', FSalary);
end;
```

### 8.3 多态

```pascal
var
  Person: TPerson;
  Employee: TEmployee;
begin
  Employee := TEmployee.Create('John', 30, 5000);
  try
    Person := Employee;  // 向上转型
    Person.Speak;        // 调用重写的方法
  finally
    Employee.Free;
  end;
end;
```

### 8.4 接口

```pascal
type
  IDrawable = interface
    ['{12345678-1234-1234-1234-123456789ABC}']
    procedure Draw;
  end;

  TShape = class(TObject, IDrawable)
  public
    procedure Draw;
  end;

procedure TShape.Draw;
begin
  WriteLn('Drawing shape');
end;
```

---

## 9. 泛型和集合

### 9.1 泛型类

```pascal
uses Generics.Collections;

var
  List: TList<Integer>;
  Dict: TDictionary<String, Integer>;
begin
  // 列表
  List := TList<Integer>.Create;
  try
    List.Add(1);
    List.Add(2);
    List.Add(3);
    
    for var Item in List do
      WriteLn(Item);
      
    WriteLn('Count: ', List.Count);
  finally
    List.Free;
  end;
  
  // 字典
  Dict := TDictionary<String, Integer>.Create;
  try
    Dict.Add('One', 1);
    Dict.Add('Two', 2);
    
    WriteLn(Dict['One']);  // 1
    WriteLn(Dict.ContainsKey('One'));  // True
  finally
    Dict.Free;
  end;
end;
```

### 9.2 泛型过程

```pascal
procedure Swap<T>(var A, B: T);
var
  Temp: T;
begin
  Temp := A;
  A := B;
  B := Temp;
end;

// 使用
var
  X, Y: Integer;
begin
  X := 1;
  Y := 2;
  Swap<Integer>(X, Y);
  // X = 2, Y = 1
end;
```

---

## 10. 多线程

### 10.1 基本线程

```pascal
uses Classes, SysUtils;

type
  TMyThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TMyThread.Execute;
begin
  // 在后台线程执行的代码
  while not Terminated do
  begin
    // 执行任务
    Sleep(100);
  end;
end;

// 使用
var
  Thread: TMyThread;
begin
  Thread := TMyThread.Create(True);  // True = 不立即启动
  Thread.FreeOnTerminate := True;    // 完成后自动释放
  Thread.Start;                      // 启动线程
end;
```

### 10.2 线程同步

```pascal
uses Classes, SyncObjs;

var
  CritSec: TCriticalSection;
  SharedData: Integer;

begin
  CritSec := TCriticalSection.Create;
  try
    // 保护共享资源
    CritSec.Enter;
    try
      SharedData := SharedData + 1;
    finally
      CritSec.Leave;
    end;
  finally
    CritSec.Free;
  end;
end;
```

### 10.3 线程安全队列

```pascal
uses Classes, SyncObjs, Generics.Collections;

type
  TThreadQueue<T> = class
  private
    FList: TList<T>;
    FCritSec: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Item: T);
    function Remove: T;
    function Count: Integer;
  end;

constructor TThreadQueue<T>.Create;
begin
  inherited Create;
  FList := TList<T>.Create;
  FCritSec := TCriticalSection.Create;
end;

destructor TThreadQueue<T>.Destroy;
begin
  FCritSec.Free;
  FList.Free;
  inherited Destroy;
end;

procedure TThreadQueue<T>.Add(const Item: T);
begin
  FCritSec.Enter;
  try
    FList.Add(Item);
  finally
    FCritSec.Leave;
  end;
end;

function TThreadQueue<T>.Remove: T;
begin
  FCritSec.Enter;
  try
    if FList.Count > 0 then
      Result := FList.Remove(FList[0])
    else
      raise Exception.Create('Queue is empty');
  finally
    FCritSec.Leave;
  end;
end;

function TThreadQueue<T>.Count: Integer;
begin
  FCritSec.Enter;
  try
    Result := FList.Count;
  finally
    FCritSec.Leave;
  end;
end;
```

---

## 11. LCL 图形界面开发

### 11.1 基本窗体

```pascal
unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Label1: TLabel;
    Edit1: TEdit;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { 私声明 }
  public
    { 公声明 }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'My Application';
  Width := 400;
  Height := 300;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Label1.Caption := 'Hello, ' + Edit1.Text;
end;

end.
```

### 11.2 常用控件

| 控件 | 说明 |
|------|------|
| `TLabel` | 标签文本 |
| `TEdit` | 单行文本输入 |
| `TMemo` | 多行文本输入 |
| `TButton` | 按钮 |
| `TCheckBox` | 复选框 |
| `TRadioButton` | 单选按钮 |
| `TComboBox` | 下拉列表 |
| `TListBox` | 列表框 |
| `TListBox` | 列表框 |
| `TGroupBox` | 分组框 |
| `TPanel` | 面板 |
| `TTabControl` | 标签页 |
| `TMainMenu` / `TPopupMenu` | 菜单 |
| `TStatusBar` | 状态栏 |
| `TToolBar` | 工具栏 |
| `TImage` | 图片显示 |
| `TPaintBox` | 自定义绘图区域 |

### 11.3 事件处理

```pascal
// 按钮点击
procedure TForm1.Button1Click(Sender: TObject);
begin
  ShowMessage('Button clicked!');
end;

// 文本变化
procedure TForm1.Edit1Change(Sender: TObject);
begin
  Label1.Caption := 'Current: ' + Edit1.Text;
end;

// 窗体大小变化
procedure TForm1.FormResize(Sender: TObject);
begin
  // 响应窗体大小变化
end;

// 鼠标事件
procedure TForm1.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  WriteLn('Mouse clicked at: ', X, ', ', Y);
end;

// 键盘事件
procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE: Close;  // ESC 关闭
    VK_RETURN: Button1.Click;  // Enter 点击按钮
  end;
end;
```

### 11.4 自定义绘图

```pascal
procedure TForm1.PaintBoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
begin
  Canvas := PaintBox.Canvas;
  
  // 绘制线条
  Canvas.Pen.Color := clRed;
  Canvas.Pen.Width := 2;
  Canvas.MoveTo(10, 10);
  Canvas.LineTo(100, 100);
  
  // 绘制矩形
  Canvas.Brush.Color := clBlue;
  Canvas.Rectangle(20, 20, 150, 100);
  
  // 绘制文本
  Canvas.Font.Color := clGreen;
  Canvas.Font.Size := 12;
  Canvas.TextOut(30, 30, 'Hello LCL');
  
  // 绘制椭圆
  Canvas.Brush.Color := clYellow;
  Canvas.Ellipse(50, 50, 150, 150);
end;
```

### 11.5 对话框

```pascal
uses Dialogs, FileCtrl;

// 消息对话框
ShowMessage('Hello!');
ShowMessageEx('Warning', 'Are you sure?', mbYesNo, 0);

// 文件选择对话框
var
  OpenDlg: TOpenDialog;
begin
  OpenDlg := TOpenDialog.Create(Self);
  try
    OpenDlg.Filter := 'Text Files|*.txt|All Files|*.*';
    if OpenDlg.Execute then
      WriteLn('Selected: ', OpenDlg.FileName);
  finally
    OpenDlg.Free;
  end;
end;

// 保存对话框
var
  SaveDlg: TSaveDialog;
begin
  SaveDlg := TSaveDialog.Create(Self);
  try
    SaveDlg.Filter := 'Text Files|*.txt';
    if SaveDlg.Execute then
      WriteLn('Save to: ', SaveDlg.FileName);
  finally
    SaveDlg.Free;
  end;
end;

// 文件夹选择
var
  SelDir: String;
begin
  if SelectDirectory('Select folder', '', SelDir) then
    WriteLn('Selected: ', SelDir);
end;

// 输入框
var
  Input: String;
begin
  Input := InputBox('Input', 'Enter name:', 'Default');
  
  // 密码框
  Input := InputBoxPassword('Password', 'Enter password:');
end;
```

---

## 12. 调试技巧

### 12.1 断点和单步

1. **设置断点**: F5 或点击行号左侧
2. **单步进入**: F7（进入函数内部）
3. **单步跳过**: F8（不进入函数）
4. **单步退出**: Shift+F8（跳出当前函数）
5. **继续执行**: F9

### 12.2 监视变量

1. **Watch List**: 右键变量 → Add watch
2. **Evaluate/Modify**: Ctrl+F7 查看/修改变量
3. **Call Stack**: 查看函数调用栈
4. **CPU View**: 查看寄存器和内存

### 12.3 日志调试

```pascal
procedure DebugLog(const Msg: String);
begin
  // 输出到调试器
  WriteLn('DEBUG: ', Msg);
  
  // 或写入日志文件
  // AppendText('debug.log', Msg + sLineBreak);
end;
```

### 12.4 条件断点

右键断点 → Breakpoint Options → 设置条件表达式，例如：
- `i = 100` 只在 i=100 时中断
- `Error <> nil` 只在 Error 存在时中断

---

## 13. 常见陷阱与最佳实践

### 13.1 内存管理陷阱

```pascal
// ❌ 错误：内存泄漏
procedure BadExample;
var
  Obj: TObject;
begin
  Obj := TObject.Create;
  // 忘记释放 Obj
end;

// ✅ 正确：使用 try...finally
procedure GoodExample;
var
  Obj: TObject;
begin
  Obj := TObject.Create;
  try
    // 使用 Obj
  finally
    Obj.Free;
  end;
end;

// ✅ 推荐：使用 FreeAndNil
FreeAndNil(Obj);  // 等价于 Obj.Free; Obj := nil;
```

### 13.2 字符串陷阱

```pascal
// ❌ 错误：在循环中拼接字符串
procedure BadStringConcat;
var
  S: String;
  i: Integer;
begin
  S := '';
  for i := 1 to 1000 do
    S := S + IntToStr(i);  // 每次创建新字符串，性能差
end;

// ✅ 正确：使用 TStringBuilder
uses SysUtils;

procedure GoodStringConcat;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 1 to 1000 do
      SB.Append(IntToStr(i));
    WriteLn(SB.ToString);
  finally
    SB.Free;
  end;
end;
```

### 13.3 类型转换陷阱

```pascal
// ❌ 错误：可能抛出异常
var
  S: String;
  I: Integer;
begin
  S := 'abc';
  I := StrToInt(S);  // 抛出 EConvertError
end;

// ✅ 正确：使用 TryStrToInt
if TryStrToInt(S, I) then
  WriteLn(I)
else
  WriteLn('Invalid number');
```

### 13.4 空指针陷阱

```pascal
// ❌ 错误：可能访问空指针
var
  Obj: TObject;
begin
  Obj.DoSomething;  // 如果 Obj = nil，崩溃
end;

// ✅ 正确：检查 nil
if Assigned(Obj) then
  Obj.DoSomething;

// 或使用 try...except
try
  Obj.DoSomething;
except
  on E: EAccessViolation do
    WriteLn('Null pointer access');
end;
```

### 13.5 浮点数比较陷阱

```pascal
// ❌ 错误：直接比较浮点数
if 0.1 + 0.2 = 0.3 then  // 可能为 False!
  WriteLn('Equal');

// ✅ 正确：使用精度比较
uses Math;

const
  EPSILON = 1e-9;

if Abs((0.1 + 0.2) - 0.3) < EPSILON then
  WriteLn('Equal');
```

### 13.6 循环陷阱

```pascal
// ❌ 错误：在循环中修改集合
var
  i: Integer;
begin
  for i := 0 to MyList.Count - 1 do
  begin
    if ShouldDelete(MyList[i]) then
      MyList.Delete(i);  // 索引会错乱!
  end;
end;

// ✅ 正确：倒序删除
for i := MyList.Count - 1 downto 0 do
  if ShouldDelete(MyList[i]) then
    MyList.Delete(i);

// 或使用 for..in 但不修改集合
for Item in MyList do
  Process(Item);  // 只读遍历
```

### 13.7 原则总结

1. **DRY** (Don't Repeat Yourself): 避免重复代码
2. **KISS** (Keep It Simple, Stupid): 保持简单
3. **YAGNI** (You Aren't Gonna Need It): 不要过度设计
4. **SOLID**: 面向对象设计原则

---

## 14. 性能优化

### 14.1 编译优化

```pascal
{$O+}  // 启用优化
{$R-}  // 关闭范围检查（发布版本）
{$Q-}  // 关闭溢出检查（发布版本）
```

编译选项：
- `-O2`: 标准优化
- `-O3`: 激进优化
- `-XX`: 启用代码优化
- `-Xs`: 精简代码

### 14.2 常见优化技巧

```pascal
// 1. 使用 const 参数避免复制
procedure Process(const Data: TStringList);  // 好
procedure Process(Data: TStringList);        // 差：复制引用

// 2. 使用 var 参数避免返回值复制
procedure GetData(var Result: TDataSet);     // 好
function GetData: TDataSet;                  // 差：复制对象

// 3. 缓存循环不变量
procedure BadLoop;
var
  i: Integer;
begin
  for i := 1 to 1000 do
    Process(MyList[i]);  // MyList.Count 每次计算
end;

procedure GoodLoop;
var
  i, Count: Integer;
begin
  Count := MyList.Count;  // 缓存
  for i := 1 to Count do
    Process(MyList[i]);
end;

// 4. 使用指针访问数组
procedure ProcessArray;
var
  Arr: array[0..999] of Integer;
  P: PInteger;
  i: Integer;
begin
  P := @Arr[0];
  for i := 0 to High(Arr) do
  begin
    P^ := i;
    Inc(P);
  end;
end;

// 5. 使用 Stream 批量读写
var
  Stream: TFileStream;
  Buffer: array[0..4095] of Byte;
begin
  Stream := TFileStream.Create('file.bin', fmOpenRead);
  try
    while Stream.Read(Buffer, SizeOf(Buffer)) > 0 do
      Process(Buffer);
  finally
    Stream.Free;
  end;
end;
```

---

## 15. 跨平台开发

### 15.1 条件编译

```pascal
{$IFDEF Windows}
  WriteLn('Windows');
{$ENDIF}

{$IFDEF Linux}
  WriteLn('Linux');
{$ENDIF}

{$IFDEF macOS}
  WriteLn('macOS');
{$ENDIF}

{$IFDEF Darwin}  // macOS
{$ENDIF}

{$IFDEF Unix}    // Linux, macOS, BSD
{$ENDIF}

{$IFDEF CPUX86}  // 32 位
{$ENDIF}

{$IFDEF CPUX64}  // 64 位
{$ENDIF}
```

### 15.2 路径处理

```pascal
uses FileUtil, SysUtils;

// 跨平台路径分隔符
var
  Path: String;
begin
  // 使用 AppendStr 或 IncludeTrailingPathDelimiter
  Path := IncludeTrailingPathDelimiter('data') + 'config.ini';
  // Windows: data\config.ini
  // Linux: data/config.ini
  
  // 或使用 ExtractFilePath
  WriteLn(ExtractFilePath(ParamStr(0)));  // 可执行文件目录
end;
```

### 15.3 平台特定代码

```pascal
type
  TPlatformHelper = class
  public
    class function GetTempDir: String;
    class function GetUserName: String;
  end;

class function TPlatformHelper.GetTempDir: String;
begin
{$IFDEF Windows}
  Result := GetEnv('TEMP');
{$ELSE}
  Result := '/tmp/';
{$ENDIF}
end;
```

---

## 附录

### A. 常用编译器指令

```pascal
{$mode objfpc}      // 使用 ObjFPC 模式
{$H+}              // 使用长字符串
{$J-}              // 只读常量
{$R+}              // 范围检查
{$Q+}              // 溢出检查
{$O+}              // 优化
{$L+}              // 调试信息
{$M+}              // 支持 RTTI
{$I+}              // I/O 检查
{$B+}              // 完全布尔短路
```

### B. 常用异常类型

| 异常类 | 说明 |
|--------|------|
| `Exception` | 基类 |
| `EConvertError` | 类型转换错误 |
| `EDivByZero` | 除零错误 |
| `EInOutError` | I/O 错误 |
| `EAccessViolation` | 访问违规 |
| `EOutOfMemory` | 内存不足 |
| `ERaiseError` | 抛出错误 |
| `EInvalidOperation` | 无效操作 |

### C. 参考资源

1. [Free Pascal 官方文档](https://www.freepascal.org/docs.html)
2. [Lazarus Wiki](https://wiki.lazarus.freepascal.org/)
3. [Free Pascal Cookbook](https://ikelaiah.github.io/free-pascal-cookbook/)
4. [Lazarus Forum](https://forum.lazarus.freepascal.org/)
5. [Stack Overflow - Lazarus 标签](https://stackoverflow.com/questions/tagged/lazarus)

---

**版本**: 1.0  
**最后更新**: 2026-06-27  
**维护者**: TinyOFD 团队
