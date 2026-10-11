# 孙家瘦身 · 精神状态测评站

密码门禁版心理健康测评。前端纯静态（GitHub Pages），后端与数据库用 Supabase。

- 客户入口：`index.html`
- 管理后台：`admin.html`

---

## 目录结构

```
.
├── index.html          客户测评页（密码门禁 → 答题 → 报告 → 长图/分享）
├── admin.html          管理后台（密码管理、使用统计）
├── config.js           ★ 唯一需要修改的配置文件
├── .nojekyll           让 GitHub Pages 不做 Jekyll 处理
├── robots.txt          禁止搜索引擎收录后台
└── supabase/
    └── schema.sql      数据库结构（在 Supabase SQL Editor 里执行一次）
```

---

## 部署步骤

### 1. 建 Supabase 项目

1. 打开 <https://supabase.com> 注册 / 登录
2. **New project** → 填项目名（如 `sunjiashoushen`）、设置数据库密码、选区域（建议 `Southeast Asia (Singapore)`，国内访问较快）
3. 等 1–2 分钟项目初始化完成

### 2. 建表

1. 左侧菜单 **SQL Editor** → **New query**
2. 把 `supabase/schema.sql` 的全部内容粘贴进去
3. 点 **Run**（右下角）

执行完最后一行会返回一行统计，应该看到 `密码总数 = 50`。

### 3. 建管理员账号

1. 左侧菜单 **Authentication** → **Users** → **Add user** → **Create new user**
2. 填邮箱 + 密码（密码请设复杂一些），勾选 **Auto Confirm User**
3. 回到 **Authentication** → **Providers** → **Email**，把 **Enable Sign-ups** 关掉（只留你一个账号）

### 4. 填配置

打开 `config.js`，填入两项（在 **Project Settings → API** 里找）：

```js
supabaseUrl:     'https://xxxxxxxxxxxx.supabase.co',   // Project URL
supabaseAnonKey: 'eyJhbGciOi...',                       // anon / public key
```

> `anon key` 是公开密钥，放在前端是正常做法；权限由数据库的 RLS 策略控制，匿名用户读不到任何密码。
> **绝对不要**把 `service_role` key 填进去。

### 5. 部署到 GitHub Pages

```bash
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

然后在 GitHub 仓库里：**Settings → Pages → Source** 选 `Deploy from a branch`，
Branch 选 `main`，目录选 `/ (root)`，保存。等 1 分钟左右生效。

访问地址：`https://<你的用户名>.github.io/<仓库名>/`
管理后台：`https://<你的用户名>.github.io/<仓库名>/admin.html`

---

## 日常使用

### 发密码给客户

后台 → 密码管理 → **＋ 生成新密码** → 填数量和批次 → 生成 → 复制。

建议一个客户发一个密码，并在「备注」里写上是谁，方便对账。

### 看数据

后台顶部 6 个数字：密码总数 / 可用密码 / 已用完 / 剩余可测次数 / 累计测评次数 / 今日测评。
「使用统计」页能看到哪种诊断类型最多、最近每一份测评的类型和评分。

### 重新启用一个用完的密码

后台 → 找到那一行 → **重置**。

### 临时停用一个密码

后台 → 找到那一行 → **停用**。客户再输入会提示「这个密码已停用，请联系客服」。

---

## 安全设计说明

| 项目 | 做法 |
|---|---|
| 密码存储 | 只存在数据库，前端源码里一个都没有 |
| 密码校验 | 服务端函数 `verify_code`，只返回「这次校验的结果」，不返回清单 |
| 次数扣减 | 服务端函数 `consume_code`，用行锁 `FOR UPDATE` 防并发重复扣次 |
| 匿名权限 | `anon` 角色对两张表**零权限**，只能调两个 RPC 函数 |
| 管理接口 | 生成密码 / 重置次数 必须已登录（`auth.uid() is not null`） |
| 缓存绕过 | 次数存服务端，清缓存、换浏览器、无痕模式都绕不过 |

---

## 常见问题

**客户打开是空白 / 一直提示网络失败？**
检查 `config.js` 里的 `supabaseUrl` 和 `supabaseAnonKey` 是否填对。浏览器 F12 → Console 看报错。

**后台登录报 "Invalid login credentials"？**
邮箱或密码不对；或第 3 步里没勾选 Auto Confirm User。

**后台看不到数据？**
确认 `schema.sql` 已完整执行（SQL Editor 里会显示历史记录）。

**改了 config.js 后网页没变化？**
GitHub Pages 有缓存，等 1–2 分钟或强制刷新（Cmd/Ctrl + Shift + R）。

**密码超过 1000 个会怎样？**
后台一次最多加载 1000 条。到这个量级建议分批管理，或联系开发者加翻页。

---

## 免责声明

本测评为心理健康自评工具，题目与常模为自研，**不是临床量表，不能用于任何医学诊断**。
页面底部已包含该声明。
