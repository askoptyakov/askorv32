module divideby3 (           
    input  logic clk,
    output logic clk_div3, clk_imem, clk_dmem);
//DESCRIPTION: Деление частоты на 3 для тактирования
//однотактного ядра и выделение двух импульсов для
//памяти инструкций(imem) и памяти данных(dmem).
//Идея в том, что при использовании синхронной памяти
//необходимо на первом такте изменить счётчик pc, на 
//втором такте считать инструкцию из памяти imem, на
//третьем такте записать/считать память данных. 
//                _   _   _   _   _   _   _   _   _
//         clk: _| |_| |_| |_| |_| |_| |_| |_| |_| |_
//    cnt_div3:   0   1   2   0   1   2   0   1   2
//				_         ___         ___         ___
//	cnt_div3[1]: |_______|   |_______|   |_______|   
//              ___         ___         ___         _
//  state_div3:    |_______|   |_______|   |_______|
//              ___       _____       _____       ___
//    clk_div3:    |_____|     |_____|     |_____|
//                ___         ___         ___        
//    clk_imem: _| 0 |_______| 0 |_______| 0 |_______
//                    ___         ___         ___        
//    clk_dmem: _____| 1 |_______| 1 |_______| 1 |___

	logic [1:0] cnt_div3 = 0;
	logic state_div3 = 1'b0;

	always_ff @(posedge clk) begin
		case (cnt_div3)
			2'd0: cnt_div3 <= 2'd1;
			2'd1: cnt_div3 <= 2'd2;
			default: cnt_div3 <= 2'd0;
		endcase
	end

	always_ff @(negedge clk) state_div3 <= cnt_div3[1];

	assign clk_div3 = cnt_div3[1] | state_div3;
    assign clk_imem = cnt_div3 == 0;
    assign clk_dmem = cnt_div3 == 1;

endmodule

//==============================================================================================
// clk_pll - базовый такт ядра и памяти от rPLL GW1NR-9 (Ч4)
//==============================================================================================
//DESCRIPTION: Такт идёт от PLL по глобальной тактовой сети, а не от триггера-делителя в логике.
//  f_out = 27 МГц * (FBDIV_SEL + 1) / (IDIV_SEL + 1)
//  VCO   = f_out * ODIV_SEL, должна быть 400..1200 МГц; ODIV_SEL: 2/4/8/16/32/48/64/80/96/112/128
//  PFD   = 27 МГц / (IDIV_SEL + 1), не меньше 3 МГц
//Примеры: 13.5 МГц - IDIV 1, FBDIV 0, ODIV 64 (VCO 864); 20.25 МГц - IDIV 3, FBDIV 2, ODIV 32 (VCO 648);
//45 МГц (рабочая частота конвейера) - IDIV 2, FBDIV 4, ODIV 16 (VCO 720); 47.25 МГц - IDIV 3, FBDIV 6, ODIV 16 (VCO 756);
//27 МГц - IDIV 0, FBDIV 0, ODIV 32 (VCO 864); 40.5 МГц - IDIV 1, FBDIV 2, ODIV 16 (VCO 648);
//54 МГц - IDIV 0, FBDIV 1, ODIV 16 (VCO 864).
//При смене частоты пересчитать SYSCLK_HZ в прошивке (fw/Core/Inc/periphery.h).
module clk_pll #(parameter FCLKIN = "27",   //Частота кварца, МГц (строка; задаёт конфигуратор в top.sv)
                 parameter int IDIV_SEL = 1, FBDIV_SEL = 0, ODIV_SEL = 64)
   (input  logic clkin,        //27 МГц с генератора платы
    output logic clkout,
    output logic lock);
    rPLL #(
        .FCLKIN(FCLKIN), .DEVICE("GW1NR-9C"),
        .DYN_IDIV_SEL("false"), .IDIV_SEL(IDIV_SEL),
        .DYN_FBDIV_SEL("false"), .FBDIV_SEL(FBDIV_SEL),
        .DYN_ODIV_SEL("false"), .ODIV_SEL(ODIV_SEL),
        .PSDA_SEL("0000"), .DYN_DA_EN("true"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1), .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) pll (
        .CLKOUT(clkout), .LOCK(lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(clkin), .CLKFB(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0), .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
    );
endmodule
