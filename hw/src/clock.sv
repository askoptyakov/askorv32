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