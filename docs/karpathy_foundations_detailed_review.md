# Karpathy 深度学习基础串讲

> 从 `micrograd` 到 `makemore`，再连接到 `nanoGPT` 的一条完整逻辑线。
>
> 这份文档重点回答：数学目标如何变成 `loss`，`logits` 如何连接到 NLL，`backward()` 如何把这个数学目标变成 neural network training。

## 0. 先看全局：所有课程其实都在重复同一个训练闭环

不管是 `micrograd` 里的小 MLP、`makemore` 的字符模型，还是后面的 Transformer，训练过程都可以压缩成：

```text
data
→ parameters 参与 forward pass
→ model output（例如 logits）
→ loss 衡量预测与答案的差距
→ backward 计算每个 parameter 对 loss 的影响
→ optimizer/update 调整 parameters
→ 下一次预测稍微变好
```

写成数学形式：

1. 模型通过参数 $\theta$ 产生预测：

   $$
   \hat y = f_\theta(x)
   $$

2. loss function 把预测和正确答案变成一个标量：

   $$
   L(\theta) = \operatorname{loss}(f_\theta(x), y)
   $$

3. backpropagation 计算：

   $$
   \frac{\partial L}{\partial \theta}
   $$

4. gradient descent 更新参数：

   $$
   \theta \leftarrow \theta - \eta \frac{\partial L}{\partial \theta}
   $$

其中 $\eta$ 是 learning rate。

后面的课程不断更换 `f` 的结构，但这个闭环没有改变。

---

## 1. Micrograd：神经网络训练为什么能工作

### 1.1 这一课解决的根问题

`micrograd` 不是先教复杂网络，而是在回答：

> 一个最终的标量 `loss`，如何告诉前面成百上千个参数分别应该往哪个方向移动？

答案是：computational graph（计算图）加 chain rule（链式法则）。

### 1.2 `Value` 表示什么

`Value` 不只是保存一个数字，还保存了这个数字是怎样计算出来的：

```python
class Value:
    data        # forward pass 得到的数值
    grad        # d(loss) / d(this Value)
    _prev       # 产生当前节点的父节点
    _op         # 当前节点使用的运算
    _backward   # 当前运算的局部求导规则
```

例如：

```python
a = Value(2.0)
b = Value(3.0)
c = a * b
d = c + a
```

forward pass 是：

$$
c = ab = 6,
\qquad
d = c+a = 8
$$

计算图是：

```text
a ──┬─> multiply ─> c ─> add ─> d
    │                         ↑
    └─────────────────────────┘
b ─────> multiply
```

### 1.3 local derivative 与 chain rule

每个运算只需要知道自己的局部导数。

对于：

$$
c=ab
$$

局部导数是：

$$
\frac{\partial c}{\partial a}=b,
\qquad
\frac{\partial c}{\partial b}=a
$$

如果最终目标是 $d$，那么：

$$
\frac{\partial d}{\partial a}
=
\frac{\partial d}{\partial c}
\frac{\partial c}{\partial a}
$$

这就是 chain rule：上游传来的梯度，乘以当前节点的局部导数，再传给父节点。

代码直觉：

```python
self.grad
→ 乘上 local derivative
→ 累加到 child/parent.grad
```

### 1.4 为什么梯度必须使用 `+=`

如果一个变量通过多条路径影响 loss，各条路径的贡献要相加。

上面的 `a` 同时直接进入 `d = c + a`，又通过 `c = a * b` 间接进入 `d`：

$$
\frac{\partial d}{\partial a}
=
\underbrace{1}_{a\to d}
+
\underbrace{b}_{a\to c\to d}
$$

所以 backward 中通常是：

```python
a.grad += contribution
```

而不是覆盖：

```python
a.grad = contribution
```

### 1.5 为什么需要 topological order

backward 必须从最终 `loss` 向前走，而且一个节点要先收到所有下游贡献，才能继续传播。

因此：

```text
先构建 topological order
→ loss.grad = 1
→ 按反向顺序调用每个节点的 _backward()
```

`loss.grad = 1` 是因为：

$$
\frac{\partial L}{\partial L}=1
$$

### 1.6 从 `Value` 到 Neuron、Layer、MLP

一个 neuron 做的事情通常是：

$$
z = w_1x_1+w_2x_2+\cdots+w_nx_n+b
$$

再经过 activation function：

$$
o=\tanh(z)
$$

多个 neuron 构成 `Layer`，多个 layer 构成 `MLP`：

```text
input x
→ Layer 1
→ activation
→ Layer 2
→ prediction
```

看起来是一个网络，本质上仍是一张由加法、乘法、`tanh` 等标量运算组成的巨大计算图。

### 1.7 micrograd 中的 loss 与 training

对于数值预测，可以使用 squared error：

$$
L=\sum_i(\hat y_i-y_i)^2
$$

当预测偏离目标时，loss 变大。调用：

```python
loss.backward()
```

得到每个参数的：

```python
p.grad  # d(loss) / d(p)
```

然后：

```python
for p in model.parameters():
    p.data += -learning_rate * p.grad
```

梯度的符号表示：如果参数略微增大，loss 会如何变化。

- `p.grad > 0`：增大 `p` 会让 loss 增大，所以应该减小 `p`。
- `p.grad < 0`：增大 `p` 会让 loss 减小，所以应该增大 `p`。

每轮训练前还必须清空梯度：

```python
for p in model.parameters():
    p.grad = 0.0
```

因为 PyTorch 和 micrograd 的梯度默认累加。忘记清零，会把不同 training step 的梯度混在一起。

### 1.8 micrograd 留下的核心认知

```text
forward：用当前参数计算预测和 loss
backward：计算每个参数对 loss 的影响
update：沿着让 loss 下降的方向移动参数
```

micrograd 解释了“怎么求梯度”。接下来的 makemore 开始解释“语言模型应该优化什么 loss”。

---

## 2. Makemore Part 1A：Count-based Bigram

### 2.1 任务是什么

makemore 的目标是生成类似训练集中的名字。

Bigram 假设非常简单：

> 下一个字符只依赖当前字符。

数学上：

$$
P(x_{t+1}\mid x_1,\ldots,x_t)
\approx
P(x_{t+1}\mid x_t)
$$

例如名字 `emma`，加入开始/结束字符 `.`：

```text
.emma.
```

得到训练样本：

```text
. -> e
e -> m
m -> m
m -> a
a -> .
```

### 2.2 Count matrix `N`

定义：

```python
N[i, j]
```

表示字符 `i` 后面出现字符 `j` 的次数。

`N` 是从数据直接统计出来的，不是 gradient descent 学出来的参数。

把第 `i` 行归一化：

$$
P_{ij}=\frac{N_{ij}}{\sum_k N_{ik}}
$$

就得到：

$$
P_{ij}=P(\text{next}=j\mid\text{current}=i)
$$

这里 `P[i]` 是完整的 next-character distribution，不是单个概率。

### 2.3 为什么可以用它生成名字

生成过程：

```text
current = '.'
→ 从 P[current] 采样 next
→ current = next
→ 重复
→ 再次采样到 '.' 时结束
```

这已经是一个完整的 language model：它能给序列分配概率，也能从概率分布采样新序列。

### 2.4 Likelihood 从哪里来

假设真实数据里有三个 bigram，模型分别给正确 next character 的概率：

```text
0.5, 0.4, 0.1
```

在模型假设下，整个数据出现的 likelihood（似然）是这些正确答案概率的乘积：

$$
\mathcal L
=
\prod_{i=1}^{N}p_i
=
0.5\times0.4\times0.1
$$

模型越好，真实数据中的字符转移应当得到越高概率，所以目标是：

$$
\max \mathcal L
$$

### 2.5 为什么变成 log-likelihood

大量小概率相乘会非常接近 0，数值不稳定。使用：

$$
\log(ab)=\log a+\log b
$$

于是：

$$
\log\mathcal L
=
\sum_i\log p_i
$$

最大化 likelihood 与最大化 log-likelihood 得到相同最优点，因为 `log` 是单调递增函数。

### 2.6 为什么变成 NLL

训练代码习惯最小化目标，而我们希望最大化 log-likelihood，所以取负号：

$$
\operatorname{NLL}
=
-\sum_i\log p_i
$$

再除以样本数，让不同 batch 的 loss 可比较：

$$
\boxed{
L
=
-\frac{1}{N}\sum_{i=1}^{N}\log p_i
}
$$

这就是 negative log-likelihood（负对数似然，NLL）。

### 2.7 NLL 到底在惩罚什么

对单个样本：

$$
L_i=-\log p_i
$$

其中 $p_i$ 只是真实 next character 的预测概率。

| 正确字符概率 | NLL | 含义 |
| ---: | ---: | --- |
| `1.0` | `0` | 完全确信正确答案 |
| `0.5` | `0.693` | 不太确定 |
| `0.1` | `2.303` | 给正确答案的概率很低 |
| `0.01` | `4.605` | 非常自信地忽略了正确答案 |

NLL 不是对所有概率求和。所有类别的概率本来就等于 1。它只检查模型给真实答案分配了多少概率。

### 2.8 Smoothing 为什么需要

未出现过的 bigram 会有 `N[i, j] == 0`，归一化后概率也是 0：

$$
-\log 0=+\infty
$$

因此可以使用简单的 add-one smoothing：

```python
P = (N + 1).float()
P /= P.sum(1, keepdim=True)
```

这表示：在真正观察数据前，先给每一种转移放入一个很小的先验 count，避免模型把任何事件判为绝对不可能。

---

## 3. Makemore Part 1B：Neural Bigram

### 3.1 为什么要把 count table 改成 neural network

Count-based bigram 已经可以工作，但它没有一般的 neural network training 结构。

Karpathy 接着构造一个最简单的神经网络版本，让下面两条路线得到相似结果：

```text
统计路线：N → normalize → P
神经网络路线：W → logits → softmax → P
```

这样就能把语言模型的概率目标连接到 micrograd 中学过的 `loss → backward → update`。

### 3.2 One-hot input 为什么乘 `W`

假设 vocabulary size 是 27：

```python
xenc.shape == (batch_size, 27)
W.shape    == (27, 27)
logits = xenc @ W
```

如果输入字符 index 是 5，那么 `xenc` 只有第 5 个位置为 1：

```text
[0, 0, 0, 0, 0, 1, 0, ...]
```

所以：

```python
xenc @ W
```

实际上选出了 `W[5]`。

因此 `W` 的每一行都对应：

> 给定一个 current character 时，对 27 个 next character 的评分。

### 3.3 `logits` 到底是什么

`logits` 是模型对各个类别输出的原始分数：

```text
logits = [-1.2, 0.7, 3.1, ...]
```

它们：

- 可以是任意实数；
- 不需要大于 0；
- 不需要加起来等于 1；
- 不是概率；
- 严格来说也不是已经归一化的 `log(probability)`。

在 bigram notebook 里可以把它们直观地看作 `log-counts`，因为 `exp(logits)` 产生正数，形式上类似 count。但更准确的理解是：

> logits 只表示类别之间的相对偏好；softmax 才把相对分数转换为概率。

给所有 logits 同时加上一个常数，softmax 结果不变：

$$
\operatorname{softmax}(z+c)=\operatorname{softmax}(z)
$$

所以绝对大小不是重点，类别之间的差值才是重点。

### 3.4 `logits → probabilities`

首先用指数函数变成正数：

$$
c_k=e^{z_k}
$$

再归一化：

$$
p_k
=
\frac{e^{z_k}}{\sum_j e^{z_j}}
$$

这就是 softmax。

代码展开写是：

```python
counts = logits.exp()
probs = counts / counts.sum(1, keepdim=True)
```

稳定、正式的写法通常是：

```python
probs = torch.softmax(logits, dim=1)
```

### 3.5 `logits` 如何与 NLL 发生关系

假设正确类别是 $y$。softmax 给它的概率是：

$$
p_y
=
\frac{e^{z_y}}{\sum_j e^{z_j}}
$$

NLL 是：

$$
L=-\log p_y
$$

代入 softmax：

$$
L
=
-\log\left(\frac{e^{z_y}}{\sum_j e^{z_j}}\right)
$$

利用对数规则：

$$
\boxed{
L=-z_y+\log\sum_j e^{z_j}
}
$$

这个公式直接揭示了 loss 对 logits 的要求：

- 第一项 `-z_y`：希望正确类别的 logit 变大；
- 第二项 `logsumexp(z)`：所有类别都在竞争，不能靠把全部 logits 一起无限增大来作弊。

所以 NLL 训练的不是一个孤立的正确分数，而是：

> 让正确类别的 logit 相对于其他类别变得更大。

### 3.6 NLL、Cross-entropy、`F.cross_entropy` 的关系

当 target 是一个确定类别时，可以把它写成 one-hot distribution $q$：

$$
q_k=
\begin{cases}
1,&k=y\\
0,&k\ne y
\end{cases}
$$

cross-entropy 是：

$$
H(q,p)=-\sum_k q_k\log p_k
$$

因为只有正确类别的 $q_y=1$，所以：

$$
H(q,p)=-\log p_y
$$

这正是 NLL。

因此，在单标签分类中：

```text
softmax + NLL
≡ cross-entropy
```

代码：

```python
loss_manual = -probs[torch.arange(batch_size), targets].log().mean()
loss_builtin = F.cross_entropy(logits, targets)
```

二者数学上等价。`F.cross_entropy` 直接接收 logits，不要提前做 softmax，因为它内部会用数值更稳定的 `log_softmax + NLL` 实现。

### 3.7 最重要的一步：loss 怎样真的改变 neural network

对单个样本，cross-entropy 对第 $k$ 个 logit 的导数是：

$$
\boxed{
\frac{\partial L}{\partial z_k}
=
p_k-\mathbb 1[k=y]
}
$$

分两种情况：

正确类别 $k=y$：

$$
\frac{\partial L}{\partial z_y}=p_y-1
$$

因为 $p_y<1$，这个梯度通常是负数。gradient descent 执行：

$$
z_y\leftarrow z_y-\eta(p_y-1)
$$

所以正确类别的 logit 会增大。

错误类别 $k\ne y$：

$$
\frac{\partial L}{\partial z_k}=p_k
$$

它是正数，所以 gradient descent 会减小错误类别的 logit。

完整效果：

```text
correct logit ↑
wrong logits ↓
→ correct probability ↑
→ NLL ↓
```

这就是 `logits → NLL → neural network training` 最核心的数学桥梁。

### 3.8 一个完整的数值例子

假设三个类别的 logits 是：

$$
z=[2,1,0]
$$

正确答案是第 2 类，也就是 index 1。

softmax 后大约是：

$$
p=[0.665,0.245,0.090]
$$

正确答案概率只有 `0.245`，所以：

$$
L=-\log(0.245)\approx1.407
$$

对 logits 的梯度是：

$$
p-onehot(y)
=
[0.665,-0.755,0.090]
$$

gradient descent 更新后：

- index 0 的 logit 减小；
- 正确的 index 1 logit 增大；
- index 2 的 logit 小幅减小。

下一次 softmax 时，正确类别的相对概率就会提高。

### 3.9 梯度怎样继续传到 `W`

因为：

$$
z=xW
$$

所以 chain rule 给出：

$$
\frac{\partial L}{\partial W}
=
x^T\frac{\partial L}{\partial z}
$$

`x` 是 one-hot，因此只有当前输入字符对应的 `W` 那一行会收到更新。

这意味着每次看到一个训练 pair：

```text
current character -> true next character
```

训练都会稍微调整当前字符对应的那一行：

```text
提高 true next character 的相对分数
降低其他 next character 的相对分数
```

大量样本反复训练以后，`W` 学出的 softmax distribution 会接近训练数据的 bigram frequency distribution。

### 3.10 Neural bigram 与 count-based bigram 的关系

| Count-based | Neural |
| --- | --- |
| `N[i, j]` 是观察次数 | `W[i, j]` 是可训练 logit |
| 行归一化得到 `P` | softmax 得到 `P` |
| 直接统计出结果 | 通过 NLL 和 gradient descent 逼近结果 |
| smoothing 防止极端概率 | regularization 约束过大的 weights |

Neural bigram 的表达能力并没有明显超过 count table。它的重要性在于建立了可扩展的训练接口：

```text
input representation
→ parameterized model
→ logits
→ cross_entropy
→ backward
→ update
```

后面只需要替换“如何产生 logits”，整个训练框架仍然成立。

---

## 4. Makemore Part 2：MLP Language Model

### 4.1 Bigram 的限制

Bigram 只看一个字符：

$$
P(x_{t+1}\mid x_t)
$$

但名字中的模式通常依赖更长上下文。例如当前都是 `m`，前面是 `em` 还是 `am`，下一字符的分布可能不同。

MLP 改为：

$$
P(x_{t+1}\mid x_{t-block\_size+1},\ldots,x_t)
$$

### 4.2 Dataset 变成 sliding context window

当：

```python
block_size = 3
```

名字 `emma` 会形成类似：

```text
... -> e
..e -> m
.em -> m
emm -> a
mma -> .
```

每产生一个 target，context 向右滑动一格：

```python
context = context[1:] + [next_index]
```

### 4.3 为什么使用 embedding

One-hot 只是离散身份，没有表达字符之间的相似性。

Embedding matrix：

```python
C.shape == (vocab_size, embedding_dim)
```

通过：

```python
emb = C[X]
```

为每个字符查出一个可训练向量。

例如：

```text
X.shape       = (32, 3)
C.shape       = (27, 10)
C[X].shape    = (32, 3, 10)
```

含义是：32 个样本，每个样本 3 个 context character，每个字符用 10 个数字表示。

### 4.4 MLP 如何产生 logits

先把 context 的 embedding 拼接起来：

```python
embcat = emb.view(-1, block_size * embedding_dim)
```

然后：

```python
h = torch.tanh(embcat @ W1 + b1)
logits = h @ W2 + b2
loss = F.cross_entropy(logits, Y)
```

数据流：

```text
character indices
→ embedding lookup
→ flatten context
→ hidden layer
→ tanh
→ output layer
→ logits for 27 next characters
→ cross_entropy
```

注意：NLL 的逻辑完全没有变化。变化的只是 logits 不再由 `xenc @ W` 直接产生，而是由 embedding 和 MLP 产生。

### 4.5 `block_size` 为什么会影响 shape

第一层的输入宽度是：

$$
block\_size\times embedding\_dim
$$

所以从：

```python
block_size = 3
embedding_dim = 2
```

改为：

```python
block_size = 5
```

维度链变化：

```text
X:       (B, 3)    → (B, 5)
C[X]:    (B, 3, 2) → (B, 5, 2)
flatten: (B, 6)    → (B, 10)
W1:      (6, H)    → (10, H)
```

`W2` 的输入仍是 hidden size，输出仍是 vocabulary size，所以不需要因为 `block_size` 改变。

### 4.6 Mini-batch、train/dev/test split

完整数据做一次 forward/backward 成本较高，所以每一步随机抽一个 mini-batch：

```python
ix = torch.randint(0, Xtr.shape[0], (batch_size,))
```

mini-batch gradient 是完整 gradient 的带噪声估计，但计算更快，可以做更多 update。

数据分为：

- training set：更新参数；
- validation/dev set：选择结构和 hyperparameters；
- test set：最后一次报告泛化表现。

如果 training loss 很低而 validation loss 明显更高，通常表示 overfitting，而不是模型真的变好了。

---

## 5. Makemore Part 3：Initialization、Activations、BatchNorm

### 5.1 这一章没有更换 loss

仍然是：

```python
logits = model(X)
loss = F.cross_entropy(logits, Y)
```

这一章研究的问题是：

> 模型结构和 loss 都写对了，为什么训练仍然可能缓慢、僵死或不稳定？

原因是 activation 和 gradient 的数值分布可能不健康。

### 5.2 输出层初始化与初始 loss

如果 vocabulary size 是 27，而且模型一开始完全不知道答案，理想情况是均匀预测：

$$
p_k=\frac1{27}
$$

对应的初始 loss：

$$
-\log\frac1{27}=\log27\approx3.296
$$

如果初始 loss 远高于这个值，说明随机 logits 差距太大，模型一开始就在没有依据地做非常自信的预测。

因此输出层常使用较小的初始 weights，让初始 logits 更接近 0、初始 distribution 更接近 uniform。

### 5.3 `tanh` saturation

隐藏层：

```python
hpreact = embcat @ W1 + b1
h = torch.tanh(hpreact)
```

导数是：

$$
\frac{d}{dx}\tanh(x)=1-\tanh^2(x)
$$

如果 `hpreact` 绝对值太大，`tanh` 输出接近 `-1` 或 `1`，导数接近 0：

```text
weights 太大
→ pre-activation 方差太大
→ tanh 大量饱和
→ backward gradient 接近 0
→ 前层参数学不动
```

### 5.4 Fan-in 与 Kaiming/Xavier initialization

一个 neuron 对许多输入加权求和。输入数量越多，未经缩放的和通常方差越大。

因此根据 `fan_in` 缩放初始化：

```python
W = torch.randn(fan_in, fan_out) / fan_in**0.5
```

目标是让 activation 的尺度跨层传播时保持稳定，而不是逐层爆炸或消失。

具体 gain 需要结合 activation function：`tanh`、ReLU 等函数保留方差的方式不同。

### 5.5 Batch Normalization 在做什么

对一个 mini-batch 的 pre-activation：

$$
\hat x=\frac{x-\mu_B}{\sqrt{\sigma_B^2+\epsilon}}
$$

再使用可学习参数：

$$
y=\gamma\hat x+\beta
$$

其中：

- `gamma` / `bngain`：学习合适的尺度；
- `beta` / `bnbias`：学习合适的偏移。

BatchNorm 把“控制 activation distribution”变成网络内部的显式操作，使训练对初始化更不敏感。

### 5.6 Training mode 与 evaluation mode

训练时，BatchNorm 使用当前 mini-batch 的 mean 和 variance。这会让同一个样本的输出受到 batch 内其他样本影响，也引入一定 regularization noise。

推理时可能只有一个样本，不能依赖当前 batch，因此使用训练期间维护的 running statistics：

```text
training: current batch mean/variance
evaluation: running mean/variance
```

忘记切换 evaluation mode，会造成生成结果不稳定或统计方式错误。

### 5.7 为什么要看 activation/gradient distribution

loss 只告诉我们最终表现，不告诉我们内部哪里坏了。

因此还要观察：

- activation 是否大量卡在饱和区域；
- gradient 是否接近 0 或异常大；
- `grad.std() / data.std()`；
- update-to-data ratio，例如 `log10(lr * grad.std() / data.std())`。

这是从“网络能运行”走向“网络可以被诊断”的关键一步。

---

## 6. Makemore Part 4：Backprop Ninja

### 6.1 这一章在补什么

micrograd 已经解释了标量计算图。Part 4 把同样的逻辑应用到真实 tensor 运算：

```text
matrix multiplication
broadcasting
softmax / cross-entropy
BatchNorm
```

目标不是以后手写所有 backward，而是能看懂 PyTorch 自动计算了什么。

### 6.2 手动拆开 cross-entropy

forward 可以展开为：

```python
logit_maxes = logits.max(1, keepdim=True).values
norm_logits = logits - logit_maxes
counts = norm_logits.exp()
counts_sum = counts.sum(1, keepdim=True)
counts_sum_inv = counts_sum ** -1
probs = counts * counts_sum_inv
logprobs = probs.log()
loss = -logprobs[range(B), Y].mean()
```

减去每行最大 logit 不改变 softmax：

$$
\frac{e^{z_k-m}}{\sum_j e^{z_j-m}}
=
\frac{e^{z_k}}{\sum_j e^{z_j}}
$$

但它避免 `exp(very_large_number)` 溢出，是 numerical stability，而不是模型逻辑变化。

### 6.3 Broadcasting 的 backward 为什么会出现 `sum`

如果 forward 中一个较小 tensor 被广播到很多位置，那么 backward 时这些位置对原 tensor 的贡献必须聚合回来。

原则：

```text
forward broadcast
↔ backward sum over broadcasted dimensions
```

例如 bias：

```python
logits = h @ W2 + b2
```

`b2` 被复用到 batch 中每个样本，因此：

```python
db2 = dlogits.sum(0)
```

### 6.4 Cross-entropy backward 的化简

虽然可以沿所有中间变量逐步反推，最后可以化简成：

```python
dlogits = probs.clone()
dlogits[torch.arange(B), Y] -= 1
dlogits /= B
```

也就是：

$$
dlogits=\frac{probs-onehot(Y)}{B}
$$

这再次连接了概率目标和训练动作：模型预测概率与真实 distribution 的差，就是 logits 直接收到的学习信号。

### 6.5 `leaf tensor` 与 `retain_grad()`

PyTorch 默认只为 leaf tensors（通常是直接创建并要求梯度的参数）保存 `.grad`。

中间 tensor 虽然参与 backward，但默认不保留 `.grad`，以节省内存。调试中如果需要检查：

```python
intermediate.retain_grad()
```

它不会改变梯度计算，只是要求 PyTorch 把该中间结果的 gradient 留下来供观察。

### 6.6 手写梯度的验证方式

把手写梯度与 autograd 结果比较：

```python
exact = torch.all(manual_grad == tensor.grad).item()
approx = torch.allclose(manual_grad, tensor.grad)
maxdiff = (manual_grad - tensor.grad).abs().max().item()
```

`maxdiff` 比只看 loss 更能定位某个局部 backward 是否错误。

---

## 7. Makemore Part 5：WaveNet 风格的层级网络

### 7.1 普通 MLP flatten 的限制

如果 context 有 8 个字符，普通 MLP 会：

```text
(B, 8, embedding_dim)
→ flatten
→ (B, 8 * embedding_dim)
```

这样一次性混合所有位置，序列的局部层级结构不明显，而且第一层参数数量会随 context length 直接增加。

### 7.2 分层合并相邻 token

WaveNet 风格结构逐层组合：

```text
a b c d e f g h
└─┘ └─┘ └─┘ └─┘
 ab  cd  ef  gh
 └───┘   └───┘
 abcd    efgh
 └────────┘
 abcdefgh
```

第一层看相邻字符，下一层组合更大的局部模式。随着深度增加，每个位置能看到的 receptive field 逐渐扩大。

### 7.3 Convolution 的真正含义

这里的 convolution 重点不是“某个特殊公式”，而是：

> 同一个局部运算使用同一组参数，在序列的不同位置滑动和复用。

也就是 parameter sharing：同一个字符模式出现在不同位置时，不需要分别学习一套参数。

相比一次性 flatten，这更符合序列中的局部模式与层级组合。

### 7.4 3D tensor 与 BatchNorm bug

层级网络经常保留时间维度：

```text
(batch, time, channels)
```

此时必须明确 BatchNorm 应该对哪些维度计算 statistics。代码能够 broadcast 并不等于统计语义正确。

检查 tensor 时不能只问“能不能运行”，还要问：

```text
每一维代表什么？
normalization 在哪些样本和时间位置上聚合？
channel dimension 是否放在 layer 期望的位置？
```

### 7.5 Part 5 没有改变的部分

最终仍然是：

```text
hierarchical network
→ logits over vocabulary
→ cross_entropy
→ backward
→ parameter update
```

这一章仍然只是升级“如何产生更有信息的 logits”。

---

## 8. 连接到 nanoGPT：同一个 loss，更强的 context mixer

仓库里的 nanoGPT 目前处于起步阶段，因此这里先建立概念桥，不把尚未完成的内容写成已经掌握的章节。

### 8.1 nanoGPT 的 bigram baseline

nanoGPT 的简单 `BigramLanguageModel` 通常直接使用：

```python
token_embedding_table = nn.Embedding(vocab_size, vocab_size)
logits = token_embedding_table(idx)
```

输入：

```text
idx.shape = (B, T)
```

输出：

```text
logits.shape = (B, T, vocab_size)
```

这里 embedding table 的每一行直接充当某个 token 的 next-token logits。它与 makemore neural bigram 的 `one_hot @ W` 数学上几乎相同：

```text
one_hot(index) @ W
≡ W[index]
≡ embedding lookup
```

### 8.2 Sequence loss 只是多了位置维度

每个 batch 有多个 time position，需要把前两维合并：

```python
B, T, C = logits.shape
logits = logits.view(B * T, C)
targets = targets.view(B * T)
loss = F.cross_entropy(logits, targets)
```

每个 `(batch, time)` 位置仍是一个分类问题：根据已有 context 预测下一个 token。

NLL 的数学逻辑没有任何改变。

### 8.3 Transformer 真正替换的是什么

Bigram baseline 只能通过当前 token 产生 logits。Transformer 会加入：

```text
token embedding
+ positional information
→ causal self-attention
→ feed-forward network
→ residual connections
→ layer normalization
→ vocabulary logits
```

self-attention 的作用是让当前位置根据前面多个位置动态收集信息。它升级的是 context representation，不是最终概率目标。

最终仍然是：

$$
P(x_{t+1}\mid x_{\le t})
=
\operatorname{softmax}(logits_t)
$$

训练仍然最小化真实 next token 的平均 NLL。

---

## 9. 一条贯穿所有课程的数学主线

### 9.1 模型的职责：产生 logits

不同模型只是使用不同方法产生 $z$：

| 模型 | logits 从哪里来 |
| --- | --- |
| Neural bigram | `one_hot(current) @ W` |
| Makemore MLP | `embedding(context) → MLP` |
| WaveNet-style | `embedding(context) → hierarchical layers` |
| Transformer | `embedding(sequence) → self-attention blocks` |

### 9.2 Softmax 的职责：把相对分数变成概率

$$
p_k=\frac{e^{z_k}}{\sum_j e^{z_j}}
$$

### 9.3 NLL 的职责：评价真实答案得到多少概率

$$
L=-\log p_y
$$

### 9.4 Backprop 的职责：计算参数怎样影响 loss

首先：

$$
\frac{\partial L}{\partial z_k}=p_k-\mathbb{1}[k=y]
$$

然后通过 chain rule：

$$
\frac{\partial L}{\partial\theta}
=
\frac{\partial L}{\partial z}
\frac{\partial z}{\partial\theta}
$$

### 9.5 Gradient descent 的职责：实际改变参数

$$
\theta\leftarrow\theta-\eta\frac{\partial L}{\partial\theta}
$$

最终因果链：

```text
真实答案 y
→ NLL 发现模型给 y 的概率太低
→ dlogits = probs - one_hot(y)
→ correct logit 收到向上的更新信号
→ wrong logits 收到向下的更新信号
→ chain rule 把信号传给所有前层 parameters
→ 下一次 forward 更倾向真实答案
```

---

## 10. 三个最容易混淆的区别

### 10.1 `logits`、`probs`、`logprobs`

```text
logits：模型原始分数，任意实数
probs：softmax(logits)，每项在 0 到 1，总和为 1
logprobs：log_softmax(logits)，也就是 log(probs) 的稳定计算
```

不要把 logits 直接解释成 probabilities。

### 10.2 Likelihood 与 loss

```text
likelihood 越大越好
log-likelihood 越大越好
negative log-likelihood 越小越好
```

它们表达同一个目标，只是方向和数值形式不同。

### 10.3 `loss` 与 `gradient`

`loss` 是一个标量，表示当前预测有多差；它没有直接告诉每个参数怎么改。

`gradient` 才是每个参数的局部修改信号：

```text
loss：现在有多差
gradient：每个参数往哪里动，能让 loss 下降
```

---

## 11. 最小代码闭环

下面的代码包含整套课程反复出现的骨架：

```python
# 1. clear gradients from the previous step
optimizer.zero_grad()

# 2. forward: model produces logits
logits = model(inputs)

# 3. objective: logits become next-token NLL internally
loss = F.cross_entropy(logits, targets)

# 4. backward: d(loss) / d(every parameter)
loss.backward()

# 5. update parameters
optimizer.step()
```

如果不用 optimizer，最后两步可以展开为：

```python
for p in model.parameters():
    p.grad = None

loss.backward()

for p in model.parameters():
    p.data += -learning_rate * p.grad
```

无论 model 内部是一个矩阵、MLP、WaveNet 还是 Transformer，这段训练骨架都基本不变。

---

## 12. 最终压缩版

### Micrograd

```text
计算图记录 forward
→ local derivatives
→ chain rule 反向传播
→ 得到 parameter.grad
→ gradient descent 更新参数
```

### Makemore Bigram

```text
字符 pair
→ next-character probability
→ likelihood
→ log-likelihood
→ negative log-likelihood
```

### Neural Bigram

```text
one-hot input
→ W 中对应的一行 logits
→ softmax probabilities
→ NLL/cross-entropy
→ dlogits = probs - one_hot(target)
→ 更新 W
```

### Makemore MLP

```text
多个 context characters
→ embeddings
→ MLP
→ 更有信息的 logits
→ 同一个 cross-entropy
```

### Initialization 与 BatchNorm

```text
控制 activation/gradient 的数值尺度
→ 避免 saturation、explosion、vanishing
→ 让训练稳定
```

### Backprop Ninja

```text
把 tensor-level autograd 拆开
→ 看懂 broadcasting、softmax、BatchNorm 的 backward
```

### WaveNet 与 Transformer

```text
使用更合理的结构整合更长 context
→ 产生更好的 logits
→ loss 和训练闭环仍然不变
```

最值得保留的一句话是：

> Neural network 的结构负责把输入变成 logits；softmax 把 logits 变成概率；NLL 衡量模型给真实答案的概率是否足够高；backprop 把这份不满意变成每个参数的梯度；gradient descent 再把参数朝降低 NLL 的方向移动。
