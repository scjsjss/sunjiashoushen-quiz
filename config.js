/* =========================================================================
   孙家瘦身 · 精神状态测评站 —— 全局配置
   -------------------------------------------------------------------------
   ★ 这是整个项目里唯一需要你手动修改的文件 ★

   只需填写下面两项（Supabase 控制台 → 左下角 Project Settings → API）：
     supabaseUrl      = Project URL         形如 https://abcdefghijk.supabase.co
     supabaseAnonKey  = anon / public 那个 key（很长的一串，以 eyJ 开头）
   -------------------------------------------------------------------------
   安全说明：anon key 是「公开密钥」，设计上就是给浏览器用的，放在前端不危险。
   真正的权限由数据库的行级安全策略（RLS）控制——匿名用户读不到任何密码。
   千万不要把 service_role key 填到这里。
   ========================================================================= */
window.APP_CONFIG = {

  /* ===== ↓↓↓ 后端地址（已自动填好，一般不用改） ↓↓↓ ===== */
  supabaseUrl:     'https://phlrezyalylpsvcmcmes.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBobHJlenlhbHlscHN2Y21jbWVzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNDA4NjIsImV4cCI6MjEwMDcxNjg2Mn0.7z5JkAhmGq3KPKORlkUkt7VUcW85ii9HBSC6O5W4bVo',
  /* ===== ↑↑↑ 后端地址 ↑↑↑ ===== */


  /* ===== 品牌与联系方式（已按你的信息填好） ===== */
  brand:    '孙家瘦身',
  site:     'sunjiashoushen.com',
  siteUrl:  'https://sunjiashoushen.com',
  wechat:   'v13510070453',          // 客服微信号
  cashback: '1',                     // 好评返现金额（元）
  shopUrl:  '',                      // 店铺链接（可选，填了会多一个「去店铺」按钮）
  topics:   '#精神状态体检 #打工人精神状态 #情绪自查',

  /* 上线后的正式网址。留空则自动取当前地址（推荐留空） */
  published: '',

  /* 每个密码可测次数——仅用于界面文案；真正的上限存在数据库里 */
  maxUses: 3
};
