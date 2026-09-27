// 云函数：获取调用者的微信 OpenID
// 参考文档：https://developers.weixin.qq.com/miniprogram/dev/framework/open-ability/login.html
// 云函数内通过 getWXContext() 直接获得调用者身份，无需 wx.login 的 code，
// 也无需在小程序侧保存 AppSecret。
const cloud = require('wx-server-sdk');

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV });

exports.main = async () => {
  const { OPENID, UNIONID, APPID } = cloud.getWXContext();
  return {
    openid: OPENID,
    unionid: UNIONID || '',
    appid: APPID,
  };
};
