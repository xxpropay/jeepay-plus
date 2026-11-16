/*
 * Copyright (c) 2021-2031, 河北计全科技有限公司 (https://www.jeequan.com & jeequan@126.com).
 * <p>
 * Licensed under the GNU LESSER GENERAL PUBLIC LICENSE 3.0;
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * <p>
 * http://www.gnu.org/licenses/lgpl.html
 * <p>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.jeequan.jeepay.pay.ctrl.payorder;

import com.jeequan.jeepay.core.entity.PayOrder;
import com.jeequan.jeepay.core.exception.BizException;
import com.jeequan.jeepay.core.model.ApiRes;
import com.jeequan.jeepay.pay.ctrl.ApiController;
import com.jeequan.jeepay.pay.rqrs.msg.ChannelRetMsg;
import com.jeequan.jeepay.pay.rqrs.payorder.ClosePayOrderRQ;
import com.jeequan.jeepay.pay.rqrs.payorder.ClosePayOrderRS;
import com.jeequan.jeepay.pay.service.ConfigContextQueryService;
import com.jeequan.jeepay.pay.service.PayOrderCloseService;
import com.jeequan.jeepay.service.impl.PayOrderService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/*
 * 关闭订单 controller
 *
 * @author xiaoyu
 * @site https://www.jeequan.com
 * @date 2022/1/25 9:19
 */
@Slf4j
@RestController
public class CloseOrderController extends ApiController {

    @Autowired private PayOrderService payOrderService;
    @Autowired private ConfigContextQueryService configContextQueryService;
    @Autowired private PayOrderCloseService payOrderCloseService;

    /**
     * @author: xiaoyu
     * @date: 2022/1/25 9:19
     * @describe: 关闭订单
     */
    @RequestMapping("/api/pay/close")
    public ApiRes closeOrder(){

        //获取参数 & 验签
        ClosePayOrderRQ rq = getRQByWithMchSign(ClosePayOrderRQ.class);

        if(StringUtils.isAllEmpty(rq.getMchOrderNo(), rq.getPayOrderId())){
            throw new BizException("mchOrderNo 和 payOrderId 不能同时为空");
        }

        PayOrder payOrder = payOrderService.queryMchOrder(rq.getMchNo(), rq.getPayOrderId(), rq.getMchOrderNo());
        if(payOrder == null){
            throw new BizException("订单不存在");
        }

        if (payOrder.getState() != PayOrder.STATE_INIT && payOrder.getState() != PayOrder.STATE_ING) {
            throw new BizException("当前订单不可关闭");
        }

        ClosePayOrderRS bizRes = new ClosePayOrderRS();

        // 订单生成状态  直接修改订单状态
        if (payOrder.getState() == PayOrder.STATE_INIT) {
            payOrderService.updateInit2Close(payOrder.getPayOrderId());
            bizRes.setChannelRetMsg(ChannelRetMsg.confirmSuccess(null));
            return ApiRes.okWithSign(bizRes, configContextQueryService.queryMchApp(rq.getMchNo(), rq.getAppId()).getAppSecret());
        }

        PayOrderCloseService.CloseResult closeResult = payOrderCloseService.close(payOrder);
        if (closeResult != PayOrderCloseService.CloseResult.CLOSED) {
            return ApiRes.customFail("订单关闭未确认: " + closeResult);
        }
        bizRes.setChannelRetMsg(ChannelRetMsg.confirmSuccess(null));

        return ApiRes.okWithSign(bizRes, configContextQueryService.queryMchApp(rq.getMchNo(), rq.getAppId()).getAppSecret());
    }

}
