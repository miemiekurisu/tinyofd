# TinyOFD 测试计划

> 基于《Free Pascal / Lazarus 开发速查手册》第 9 章测试规范  
> 目标：100% 代码覆盖率，完整的边界值、异常值、随机值测试

---

## 测试策略总览

### 测试层次

```
Level 1: 单元测试 (Unit Tests)
  ├─ 每个 public 函数必须有测试
  ├─ 每个 protected/private 复杂逻辑必须通过 public 行为覆盖
  ├─ 每个异常分支必须有测试
  └─ 覆盖率目标：100%

Level 2: 集成测试 (Integration Tests)
  ├─ 模块间交互测试
  ├─ OFD 文件完整解析流程
  └─ 渲染管线端到端测试

Level 3: 系统测试 (System Tests)
  ├─ 完整 OFD 阅读器功能测试
  ├─ 性能基准测试
  └─ 压力测试

Level 4: 安全测试 (Security Tests)
  ├─ Zip Slip 路径穿越
  ├─ 畸形 XML 处理
  ├─ 超大文件处理
  └─ 内存溢出测试
```

---

## 测试用例设计原则

### 1. 边界值分析

对每个输入参数，测试：
- **最小值** (Min)
- **略大于最小值** (Min+)
- **正常值** (Normal)
- **略小于最大值** (Max-)
- **最大值** (Max)
- **越界值** (Max+)

**示例**: 页面索引测试
```pascal
procedure TestGetPageEntryByIndex;
begin
  // 边界值
  TestGetPageEntryByIndex(0);           // 最小值
  TestGetPageEntryByIndex(1);           // 略大于最小值
  TestGetPageEntryByIndex(PageCount-1); // 最大值
  TestGetPageEntryByIndex(PageCount);   // 越界 - 应抛出异常
  TestGetPageEntryByIndex(-1);          // 越界 - 应抛出异常
  TestGetPageEntryByIndex(MaxInt);      // 极限值 - 应抛出异常
  
  // 随机合法值
  for I := 0 to 99 do
  begin
    RandIndex := Random(PageCount);
    TestGetPageEntryByIndex(RandIndex); // 随机合法页码
  end;
end;
```

### 2. 异常路径测试

对每个可能抛出异常的场景：
- **空输入**
- **非法输入**
- **类型不匹配**
- **资源不存在**
- **权限不足**

**示例**: 文件读取测试
```pascal
procedure TestReadAsString;
begin
  // 正常路径
  TestReadAsString('OFD.xml');
  
  // 异常路径
  TestReadAsString('');                    // 空路径 - 应抛出异常
  TestReadAsString('../escape.txt');       // 路径穿越 - 应抛出异常
  TestReadAsString('nonexistent.xml');     // 文件不存在 - 应抛出异常
  TestReadAsString('/absolute/path.xml');  // 绝对路径 - 应抛出异常
end;
```

### 3. 随机测试 (可复现)

```pascal
procedure TestRandomMatrixOperations;
const
  TEST_SEED = 12345;  // 固定 seed 保证可复现
var
  I: Integer;
  M1, M2, MResult: TOFDMatrix;
  X, Y: Double;
begin
  RandSeed := TEST_SEED;
  
  for I := 1 to 1000 do
  begin
    // 随机矩阵
    M1 := CreateRandomMatrix;
    M2 := CreateRandomMatrix;
    
    // 随机点
    X := Random(1000) - 500;
    Y := Random(1000) - 500;
    
    // 测试矩阵乘法
    MResult := MatrixMultiply(M1, M2);
    
    // 测试点变换
    TransformPointByMatrix(MResult, X, Y);
    
    // 验证合理性
    CheckTrue(Abs(X) < 10000);  // 防止溢出
    CheckTrue(Abs(Y) < 10000);
  end;
end;
```

---

## Phase 1: 基础架构测试

### 1.4 矩阵运算单元测试

**测试文件**: `tests/ofdcore/test_matrix.pas`

**测试用例**:

```pascal
unit test_matrix;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TestFramework, ofd_types;

type
  TMatrixTest = class(TTestCase)
  public
    procedure TestMatrixIdentity;
    procedure TestMatrixMultiply;
    procedure TestMatrixTranslate;
    procedure TestMatrixScale;
    procedure TestMatrixRotate;
    procedure TestMatrixInverse;
    procedure TestMatrixTranspose;
    procedure TestMatrixDeterminant;
    procedure TestTransformPointByMatrix;
    procedure TestTransformRectByMatrix;
    procedure TestMatrixInverseException;
    procedure TestMatrixBoundaryValues;
  end;

implementation

procedure TMatrixTest.TestMatrixIdentity;
var
  M: TOFDMatrix;
begin
  M := MatrixIdentity;
  
  // 对角线为 1
  CheckEquals(1.0, M[0,0]);
  CheckEquals(1.0, M[1,1]);
  CheckEquals(1.0, M[2,2]);
  
  // 其他为 0
  CheckEquals(0.0, M[0,1]);
  CheckEquals(0.0, M[0,2]);
  CheckEquals(0.0, M[1,0]);
  CheckEquals(0.0, M[1,2]);
  CheckEquals(0.0, M[2,0]);
  CheckEquals(0.0, M[2,1]);
end;

procedure TMatrixTest.TestMatrixMultiply;
var
  A, B, C: TOFDMatrix;
begin
  // 创建测试矩阵
  A := MatrixIdentity;
  A[0,0] := 2; A[0,1] := 3; A[0,2] := 4;
  A[1,0] := 5; A[1,1] := 6; A[1,2] := 7;
  A[2,0] := 8; A[2,1] := 9; A[2,2] := 10;
  
  B := MatrixIdentity;
  B[0,0] := 11; B[0,1] := 12; B[0,2] := 13;
  B[1,0] := 14; B[1,1] := 15; B[1,2] := 16;
  B[2,0] := 17; B[2,1] := 18; B[2,2] := 19;
  
  C := MatrixMultiply(A, B);
  
  // 验证计算结果
  CheckEquals(110.0, C[0,0]);  // 2*11 + 3*14 + 4*17
  CheckEquals(122.0, C[0,1]);  // 2*12 + 3*15 + 4*18
  CheckEquals(134.0, C[0,2]);  // 2*13 + 3*16 + 4*19
  // ... 验证所有元素
end;

procedure TMatrixTest.TestMatrixInverse;
var
  M, Minv: TOFDMatrix;
begin
  // 创建可逆矩阵
  M := MatrixIdentity;
  M[0,0] := 2; M[0,1] := 1; M[0,2] := 0;
  M[1,0] := 1; M[1,1] := 2; M[1,2] := 1;
  M[2,0] := 0; M[2,1] := 1; M[2,2] := 2;
  
  Minv := MatrixInverse(M);
  
  // 验证 M × Minv = I
  var I := MatrixMultiply(M, Minv);
  CheckEquals(1.0, I[0,0], 1e-10);
  CheckEquals(0.0, I[0,1], 1e-10);
  // ... 验证所有元素
end;

procedure TMatrixTest.TestMatrixInverseException;
var
  M: TOFDMatrix;
begin
  // 创建奇异矩阵（不可逆）
  M := MatrixIdentity;
  M[0,0] := 1; M[0,1] := 2; M[0,2] := 3;
  M[1,0] := 4; M[1,1] := 5; M[1,2] := 6;
  M[2,0] := 7; M[2,1] := 8; M[2,2] := 9;  // 行列式 = 0
  
  // 应抛出异常
  CheckException(
    procedure begin MatrixInverse(M); end,
    'EConvertError'
  );
end;

procedure TMatrixTest.TestTransformPointByMatrix;
var
  M: TOFDMatrix;
  X, Y: Double;
begin
  // 测试平移变换
  M := MatrixIdentity;
  M[0,2] := 10;  // X 平移 10
  M[1,2] := 20;  // Y 平移 20
  
  X := 0; Y := 0;
  TransformPointByMatrix(M, X, Y);
  
  CheckEquals(10.0, X, 1e-10);
  CheckEquals(20.0, Y, 1e-10);
end;

procedure TMatrixTest.TestTransformRectByMatrix;
var
  M: TOFDMatrix;
  X, Y, W, H: Double;
begin
  M := MatrixIdentity;
  M[0,0] := 2;  // X 方向缩放 2 倍
  M[1,1] := 3;  // Y 方向缩放 3 倍
  
  X := 0; Y := 0;
  W := 10; H := 20;
  
  TransformRectByMatrix(M, X, Y, W, H);
  
  CheckEquals(0.0, X, 1e-10);
  CheckEquals(0.0, Y, 1e-10);
  CheckEquals(20.0, W, 1e-10);  // 10 * 2
  CheckEquals(60.0, H, 1e-10);  // 20 * 3
end;

procedure TMatrixTest.TestMatrixBoundaryValues;
var
  M: TOFDMatrix;
  X, Y: Double;
begin
  // 测试极大值
  M := MatrixIdentity;
  M[0,0] := 1e10;
  M[1,1] := 1e10;
  
  X := 1; Y := 1;
  TransformPointByMatrix(M, X, Y);
  
  CheckTrue(Abs(X) > 1e9);  // 应放大
  CheckTrue(Abs(Y) > 1e9);
  
  // 测试极小值
  M := MatrixIdentity;
  M[0,0] := 1e-10;
  M[1,1] := 1e-10;
  
  X := 1000; Y := 1000;
  TransformPointByMatrix(M, X, Y);
  
  CheckTrue(Abs(X) < 1e-6);  // 应缩小
  CheckTrue(Abs(Y) < 1e-6);
end;

end.
```

---

## 测试执行流程

### 每个 Phase 的执行步骤

1. **实现功能代码**
   - 遵循速查手册规范
   - 添加完整注释
   - 处理所有异常路径

2. **编写单元测试**
   - 正常输入测试
   - 边界值测试
   - 异常值测试
   - 随机值测试（可复现 seed）
   - 极限值测试

3. **运行测试**
   ```bash
   # 运行单元测试
   script/test.ps1
   
   # 查看覆盖率报告
   _tmp/coverage/index.html
   ```

4. **检查覆盖率**
   - 目标：100%
   - 未覆盖的代码必须添加测试或说明原因

5. **集成测试**
   - 使用 testfile 中的真实 OFD 文件
   - 验证完整功能流程

6. **参考速查手册对齐**
   - 检查是否符合最佳实践
   - 检查是否有违背规范的地方
   - 记录偏差和改进计划

7. **编写测试报告**
   - 测试用例数量
   - 覆盖率统计
   - 发现的问题
   - 性能指标

---

## 测试数据

### 测试文件清单

```
testfile/
├── atemp.ofd              # 包含文字 + 图片
├── text_only.ofd          # 纯文字
├── image_only.ofd         # 纯图片
├── multi_page.ofd         # 多页文档
├── complex.ofd            # 复杂内容（路径 + 渐变）
├── empty.ofd              # 空文档（异常测试）
├── corrupted.ofd          # 损坏文件（异常测试）
└── large.ofd              # 大文件（性能测试）
```

### 测试数据生成

```pascal
// 生成随机 OFD 测试文件
procedure GenerateRandomOFDTestFile;
var
  Doc: TOFDDocument;
  I, J: Integer;
begin
  Doc := CreateTestDocument;
  
  // 添加 100 个随机文本对象
  for I := 0 to 99 do
  begin
    AddRandomTextObject(Doc,
      Random(1000),  // X
      Random(1000),  // Y
      Random(10) + 5, // 字体大小
      GetRandomString  // 随机文本
    );
  end;
  
  // 添加 50 个随机图片对象
  for I := 0 to 49 do
  begin
    AddRandomImageObject(Doc,
      Random(1000),
      Random(1000),
      Random(200) + 50,  // 宽度
      Random(200) + 50   // 高度
    );
  end;
  
  SaveTestDocument(Doc, '_tmp/test/random_test.ofd');
  Doc.Free;
end;
```

---

## 质量检查清单

### 每个 Phase 验收标准

- [ ] 所有 public 函数都有单元测试
- [ ] 边界值测试覆盖（Min, Min+, Normal, Max-, Max, Max+）
- [ ] 异常路径测试覆盖
- [ ] 随机测试可复现（固定 seed）
- [ ] 代码覆盖率 ≥ 100%
- [ ] 无编译警告
- [ ] 集成测试通过
- [ ] 性能测试通过（无显著退化）
- [ ] 参考速查手册，无重大偏差
- [ ] 文档已更新
- [ ] 测试报告已生成

---

**创建日期**: 2026-06-27  
**最后更新**: 2026-06-27  
**版本**: 1.0
