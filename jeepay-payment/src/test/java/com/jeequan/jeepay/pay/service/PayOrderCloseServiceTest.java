package com.jeequan.jeepay.pay.service;

import com.jeequan.jeepay.core.entity.PayOrder;
import com.jeequan.jeepay.pay.channel.IPayOrderCloseService;
import com.jeequan.jeepay.pay.rqrs.msg.ChannelRetMsg;
import com.jeequan.jeepay.service.impl.PayOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationContext;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class PayOrderCloseServiceTest {
    private final ApplicationContext applicationContext = mock(ApplicationContext.class);
    private final ConfigContextQueryService configService = mock(ConfigContextQueryService.class);
    private final PayOrderService orderService = mock(PayOrderService.class);
    private final IPayOrderCloseService channelService = mock(IPayOrderCloseService.class);
    private PayOrderCloseService service;
    private PayOrder order;

    @BeforeEach
    void setUp() {
        service = new PayOrderCloseService(applicationContext, configService, orderService);
        order = new PayOrder();
        order.setPayOrderId("P100");
        order.setMchNo("M100");
        order.setAppId("A100");
        order.setIfCode("wxpay");
        when(applicationContext.getBean("wxpayPayOrderCloseService", IPayOrderCloseService.class))
                .thenReturn(channelService);
    }

    @Test
    void closesLocalOrderOnlyWhenChannelConfirmsSuccess() throws Exception {
        when(channelService.close(any(), any())).thenReturn(ChannelRetMsg.confirmSuccess(null));
        when(orderService.updateIng2Close("P100")).thenReturn(true);

        assertEquals(PayOrderCloseService.CloseResult.CLOSED, service.close(order));
        verify(orderService).updateIng2Close("P100");
    }

    @Test
    void keepsOrderPendingWhenChannelResultIsUnknown() throws Exception {
        when(channelService.close(any(), any())).thenReturn(null);

        assertEquals(PayOrderCloseService.CloseResult.UNKNOWN, service.close(order));
        verify(orderService, never()).updateIng2Close(anyString());
    }
}
