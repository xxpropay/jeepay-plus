package com.jeequan.jeepay.pay.channel.ysfpay;

import com.alibaba.fastjson.JSONObject;
import com.jeequan.jeepay.core.exception.BizException;
import com.jeequan.jeepay.core.model.params.ysf.YsfpayIsvsubMchParams;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class YsfpayPaymentServiceTest {
    @Test
    void rejectsBarPaymentWithoutConfiguredTerminalId() {
        BizException ex = assertThrows(BizException.class,
                () -> YsfpayPaymentService.applyTerminalId(new JSONObject(), new YsfpayIsvsubMchParams()));
        assertEquals("云闪付终端号未配置", ex.getMessage());
    }

    @Test
    void usesTrimmedSubMerchantTerminalId() {
        YsfpayIsvsubMchParams params = new YsfpayIsvsubMchParams();
        params.setTermId(" 01727367 ");
        JSONObject request = new JSONObject();
        YsfpayPaymentService.applyTerminalId(request, params);
        assertEquals("01727367", request.getString("termId"));
    }
}
