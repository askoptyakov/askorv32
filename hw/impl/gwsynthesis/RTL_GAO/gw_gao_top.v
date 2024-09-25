module gw_gao(
    \riscv/PC[31] ,
    \riscv/PC[30] ,
    \riscv/PC[29] ,
    \riscv/PC[28] ,
    \riscv/PC[27] ,
    \riscv/PC[26] ,
    \riscv/PC[25] ,
    \riscv/PC[24] ,
    \riscv/PC[23] ,
    \riscv/PC[22] ,
    \riscv/PC[21] ,
    \riscv/PC[20] ,
    \riscv/PC[19] ,
    \riscv/PC[18] ,
    \riscv/PC[17] ,
    \riscv/PC[16] ,
    \riscv/PC[15] ,
    \riscv/PC[14] ,
    \riscv/PC[13] ,
    \riscv/PC[12] ,
    \riscv/PC[11] ,
    \riscv/PC[10] ,
    \riscv/PC[9] ,
    \riscv/PC[8] ,
    \riscv/PC[7] ,
    \riscv/PC[6] ,
    \riscv/PC[5] ,
    \riscv/PC[4] ,
    \riscv/PC[3] ,
    \riscv/PC[2] ,
    \riscv/PC[1] ,
    \riscv/PC[0] ,
    \riscv/Instr[31] ,
    \riscv/Instr[30] ,
    \riscv/Instr[29] ,
    \riscv/Instr[28] ,
    \riscv/Instr[27] ,
    \riscv/Instr[26] ,
    \riscv/Instr[25] ,
    \riscv/Instr[24] ,
    \riscv/Instr[23] ,
    \riscv/Instr[22] ,
    \riscv/Instr[21] ,
    \riscv/Instr[20] ,
    \riscv/Instr[19] ,
    \riscv/Instr[18] ,
    \riscv/Instr[17] ,
    \riscv/Instr[16] ,
    \riscv/Instr[15] ,
    \riscv/Instr[14] ,
    \riscv/Instr[13] ,
    \riscv/Instr[12] ,
    \riscv/Instr[11] ,
    \riscv/Instr[10] ,
    \riscv/Instr[9] ,
    \riscv/Instr[8] ,
    \riscv/Instr[7] ,
    \riscv/Instr[6] ,
    \riscv/Instr[5] ,
    \riscv/Instr[4] ,
    \riscv/Instr[3] ,
    \riscv/Instr[2] ,
    \riscv/Instr[1] ,
    \riscv/Instr[0] ,
    \riscv/rf[2][31] ,
    \riscv/rf[2][30] ,
    \riscv/rf[2][29] ,
    \riscv/rf[2][28] ,
    \riscv/rf[2][27] ,
    \riscv/rf[2][26] ,
    \riscv/rf[2][25] ,
    \riscv/rf[2][24] ,
    \riscv/rf[2][23] ,
    \riscv/rf[2][22] ,
    \riscv/rf[2][21] ,
    \riscv/rf[2][20] ,
    \riscv/rf[2][19] ,
    \riscv/rf[2][18] ,
    \riscv/rf[2][17] ,
    \riscv/rf[2][16] ,
    \riscv/rf[2][15] ,
    \riscv/rf[2][14] ,
    \riscv/rf[2][13] ,
    \riscv/rf[2][12] ,
    \riscv/rf[2][11] ,
    \riscv/rf[2][10] ,
    \riscv/rf[2][9] ,
    \riscv/rf[2][8] ,
    \riscv/rf[2][7] ,
    \riscv/rf[2][6] ,
    \riscv/rf[2][5] ,
    \riscv/rf[2][4] ,
    \riscv/rf[2][3] ,
    \riscv/rf[2][2] ,
    \riscv/rf[2][1] ,
    \riscv/rf[2][0] ,
    \riscv/rf[3][31] ,
    \riscv/rf[3][30] ,
    \riscv/rf[3][29] ,
    \riscv/rf[3][28] ,
    \riscv/rf[3][27] ,
    \riscv/rf[3][26] ,
    \riscv/rf[3][25] ,
    \riscv/rf[3][24] ,
    \riscv/rf[3][23] ,
    \riscv/rf[3][22] ,
    \riscv/rf[3][21] ,
    \riscv/rf[3][20] ,
    \riscv/rf[3][19] ,
    \riscv/rf[3][18] ,
    \riscv/rf[3][17] ,
    \riscv/rf[3][16] ,
    \riscv/rf[3][15] ,
    \riscv/rf[3][14] ,
    \riscv/rf[3][13] ,
    \riscv/rf[3][12] ,
    \riscv/rf[3][11] ,
    \riscv/rf[3][10] ,
    \riscv/rf[3][9] ,
    \riscv/rf[3][8] ,
    \riscv/rf[3][7] ,
    \riscv/rf[3][6] ,
    \riscv/rf[3][5] ,
    \riscv/rf[3][4] ,
    \riscv/rf[3][3] ,
    \riscv/rf[3][2] ,
    \riscv/rf[3][1] ,
    \riscv/rf[3][0] ,
    \riscv/rf[7][31] ,
    \riscv/rf[7][30] ,
    \riscv/rf[7][29] ,
    \riscv/rf[7][28] ,
    \riscv/rf[7][27] ,
    \riscv/rf[7][26] ,
    \riscv/rf[7][25] ,
    \riscv/rf[7][24] ,
    \riscv/rf[7][23] ,
    \riscv/rf[7][22] ,
    \riscv/rf[7][21] ,
    \riscv/rf[7][20] ,
    \riscv/rf[7][19] ,
    \riscv/rf[7][18] ,
    \riscv/rf[7][17] ,
    \riscv/rf[7][16] ,
    \riscv/rf[7][15] ,
    \riscv/rf[7][14] ,
    \riscv/rf[7][13] ,
    \riscv/rf[7][12] ,
    \riscv/rf[7][11] ,
    \riscv/rf[7][10] ,
    \riscv/rf[7][9] ,
    \riscv/rf[7][8] ,
    \riscv/rf[7][7] ,
    \riscv/rf[7][6] ,
    \riscv/rf[7][5] ,
    \riscv/rf[7][4] ,
    \riscv/rf[7][3] ,
    \riscv/rf[7][2] ,
    \riscv/rf[7][1] ,
    \riscv/rf[7][0] ,
    \riscv/rf[4][31] ,
    \riscv/rf[4][30] ,
    \riscv/rf[4][29] ,
    \riscv/rf[4][28] ,
    \riscv/rf[4][27] ,
    \riscv/rf[4][26] ,
    \riscv/rf[4][25] ,
    \riscv/rf[4][24] ,
    \riscv/rf[4][23] ,
    \riscv/rf[4][22] ,
    \riscv/rf[4][21] ,
    \riscv/rf[4][20] ,
    \riscv/rf[4][19] ,
    \riscv/rf[4][18] ,
    \riscv/rf[4][17] ,
    \riscv/rf[4][16] ,
    \riscv/rf[4][15] ,
    \riscv/rf[4][14] ,
    \riscv/rf[4][13] ,
    \riscv/rf[4][12] ,
    \riscv/rf[4][11] ,
    \riscv/rf[4][10] ,
    \riscv/rf[4][9] ,
    \riscv/rf[4][8] ,
    \riscv/rf[4][7] ,
    \riscv/rf[4][6] ,
    \riscv/rf[4][5] ,
    \riscv/rf[4][4] ,
    \riscv/rf[4][3] ,
    \riscv/rf[4][2] ,
    \riscv/rf[4][1] ,
    \riscv/rf[4][0] ,
    \riscv/rf[5][31] ,
    \riscv/rf[5][30] ,
    \riscv/rf[5][29] ,
    \riscv/rf[5][28] ,
    \riscv/rf[5][27] ,
    \riscv/rf[5][26] ,
    \riscv/rf[5][25] ,
    \riscv/rf[5][24] ,
    \riscv/rf[5][23] ,
    \riscv/rf[5][22] ,
    \riscv/rf[5][21] ,
    \riscv/rf[5][20] ,
    \riscv/rf[5][19] ,
    \riscv/rf[5][18] ,
    \riscv/rf[5][17] ,
    \riscv/rf[5][16] ,
    \riscv/rf[5][15] ,
    \riscv/rf[5][14] ,
    \riscv/rf[5][13] ,
    \riscv/rf[5][12] ,
    \riscv/rf[5][11] ,
    \riscv/rf[5][10] ,
    \riscv/rf[5][9] ,
    \riscv/rf[5][8] ,
    \riscv/rf[5][7] ,
    \riscv/rf[5][6] ,
    \riscv/rf[5][5] ,
    \riscv/rf[5][4] ,
    \riscv/rf[5][3] ,
    \riscv/rf[5][2] ,
    \riscv/rf[5][1] ,
    \riscv/rf[5][0] ,
    \dmem/RAM[0][31] ,
    \dmem/RAM[0][30] ,
    \dmem/RAM[0][29] ,
    \dmem/RAM[0][28] ,
    \dmem/RAM[0][27] ,
    \dmem/RAM[0][26] ,
    \dmem/RAM[0][25] ,
    \dmem/RAM[0][24] ,
    \dmem/RAM[0][23] ,
    \dmem/RAM[0][22] ,
    \dmem/RAM[0][21] ,
    \dmem/RAM[0][20] ,
    \dmem/RAM[0][19] ,
    \dmem/RAM[0][18] ,
    \dmem/RAM[0][17] ,
    \dmem/RAM[0][16] ,
    \dmem/RAM[0][15] ,
    \dmem/RAM[0][14] ,
    \dmem/RAM[0][13] ,
    \dmem/RAM[0][12] ,
    \dmem/RAM[0][11] ,
    \dmem/RAM[0][10] ,
    \dmem/RAM[0][9] ,
    \dmem/RAM[0][8] ,
    \dmem/RAM[0][7] ,
    \dmem/RAM[0][6] ,
    \dmem/RAM[0][5] ,
    \dmem/RAM[0][4] ,
    \dmem/RAM[0][3] ,
    \dmem/RAM[0][2] ,
    \dmem/RAM[0][1] ,
    \dmem/RAM[0][0] ,
    \riscv/rf[9][31] ,
    \riscv/rf[9][30] ,
    \riscv/rf[9][29] ,
    \riscv/rf[9][28] ,
    \riscv/rf[9][27] ,
    \riscv/rf[9][26] ,
    \riscv/rf[9][25] ,
    \riscv/rf[9][24] ,
    \riscv/rf[9][23] ,
    \riscv/rf[9][22] ,
    \riscv/rf[9][21] ,
    \riscv/rf[9][20] ,
    \riscv/rf[9][19] ,
    \riscv/rf[9][18] ,
    \riscv/rf[9][17] ,
    \riscv/rf[9][16] ,
    \riscv/rf[9][15] ,
    \riscv/rf[9][14] ,
    \riscv/rf[9][13] ,
    \riscv/rf[9][12] ,
    \riscv/rf[9][11] ,
    \riscv/rf[9][10] ,
    \riscv/rf[9][9] ,
    \riscv/rf[9][8] ,
    \riscv/rf[9][7] ,
    \riscv/rf[9][6] ,
    \riscv/rf[9][5] ,
    \riscv/rf[9][4] ,
    \riscv/rf[9][3] ,
    \riscv/rf[9][2] ,
    \riscv/rf[9][1] ,
    \riscv/rf[9][0] ,
    \dmem/RAM[4][31] ,
    \dmem/RAM[4][30] ,
    \dmem/RAM[4][29] ,
    \dmem/RAM[4][28] ,
    \dmem/RAM[4][27] ,
    \dmem/RAM[4][26] ,
    \dmem/RAM[4][25] ,
    \dmem/RAM[4][24] ,
    \dmem/RAM[4][23] ,
    \dmem/RAM[4][22] ,
    \dmem/RAM[4][21] ,
    \dmem/RAM[4][20] ,
    \dmem/RAM[4][19] ,
    \dmem/RAM[4][18] ,
    \dmem/RAM[4][17] ,
    \dmem/RAM[4][16] ,
    \dmem/RAM[4][15] ,
    \dmem/RAM[4][14] ,
    \dmem/RAM[4][13] ,
    \dmem/RAM[4][12] ,
    \dmem/RAM[4][11] ,
    \dmem/RAM[4][10] ,
    \dmem/RAM[4][9] ,
    \dmem/RAM[4][8] ,
    \dmem/RAM[4][7] ,
    \dmem/RAM[4][6] ,
    \dmem/RAM[4][5] ,
    \dmem/RAM[4][4] ,
    \dmem/RAM[4][3] ,
    \dmem/RAM[4][2] ,
    \dmem/RAM[4][1] ,
    \dmem/RAM[4][0] ,
    \dmem/a[31] ,
    \dmem/a[30] ,
    \dmem/a[29] ,
    \dmem/a[28] ,
    \dmem/a[27] ,
    \dmem/a[26] ,
    \dmem/a[25] ,
    \dmem/a[24] ,
    \dmem/a[23] ,
    \dmem/a[22] ,
    \dmem/a[21] ,
    \dmem/a[20] ,
    \dmem/a[19] ,
    \dmem/a[18] ,
    \dmem/a[17] ,
    \dmem/a[16] ,
    \dmem/a[15] ,
    \dmem/a[14] ,
    \dmem/a[13] ,
    \dmem/a[12] ,
    \dmem/a[11] ,
    \dmem/a[10] ,
    \dmem/a[9] ,
    \dmem/a[8] ,
    \dmem/a[7] ,
    \dmem/a[6] ,
    \dmem/a[5] ,
    \dmem/a[4] ,
    \dmem/a[3] ,
    \dmem/a[2] ,
    \dmem/a[1] ,
    \dmem/a[0] ,
    \dmem/wd[31] ,
    \dmem/wd[30] ,
    \dmem/wd[29] ,
    \dmem/wd[28] ,
    \dmem/wd[27] ,
    \dmem/wd[26] ,
    \dmem/wd[25] ,
    \dmem/wd[24] ,
    \dmem/wd[23] ,
    \dmem/wd[22] ,
    \dmem/wd[21] ,
    \dmem/wd[20] ,
    \dmem/wd[19] ,
    \dmem/wd[18] ,
    \dmem/wd[17] ,
    \dmem/wd[16] ,
    \dmem/wd[15] ,
    \dmem/wd[14] ,
    \dmem/wd[13] ,
    \dmem/wd[12] ,
    \dmem/wd[11] ,
    \dmem/wd[10] ,
    \dmem/wd[9] ,
    \dmem/wd[8] ,
    \dmem/wd[7] ,
    \dmem/wd[6] ,
    \dmem/wd[5] ,
    \dmem/wd[4] ,
    \dmem/wd[3] ,
    \dmem/wd[2] ,
    \dmem/wd[1] ,
    \dmem/wd[0] ,
    \riscv/alu_A[31] ,
    \riscv/alu_A[30] ,
    \riscv/alu_A[29] ,
    \riscv/alu_A[28] ,
    \riscv/alu_A[27] ,
    \riscv/alu_A[26] ,
    \riscv/alu_A[25] ,
    \riscv/alu_A[24] ,
    \riscv/alu_A[23] ,
    \riscv/alu_A[22] ,
    \riscv/alu_A[21] ,
    \riscv/alu_A[20] ,
    \riscv/alu_A[19] ,
    \riscv/alu_A[18] ,
    \riscv/alu_A[17] ,
    \riscv/alu_A[16] ,
    \riscv/alu_A[15] ,
    \riscv/alu_A[14] ,
    \riscv/alu_A[13] ,
    \riscv/alu_A[12] ,
    \riscv/alu_A[11] ,
    \riscv/alu_A[10] ,
    \riscv/alu_A[9] ,
    \riscv/alu_A[8] ,
    \riscv/alu_A[7] ,
    \riscv/alu_A[6] ,
    \riscv/alu_A[5] ,
    \riscv/alu_A[4] ,
    \riscv/alu_A[3] ,
    \riscv/alu_A[2] ,
    \riscv/alu_A[1] ,
    \riscv/alu_A[0] ,
    \riscv/alu_B[31] ,
    \riscv/alu_B[30] ,
    \riscv/alu_B[29] ,
    \riscv/alu_B[28] ,
    \riscv/alu_B[27] ,
    \riscv/alu_B[26] ,
    \riscv/alu_B[25] ,
    \riscv/alu_B[24] ,
    \riscv/alu_B[23] ,
    \riscv/alu_B[22] ,
    \riscv/alu_B[21] ,
    \riscv/alu_B[20] ,
    \riscv/alu_B[19] ,
    \riscv/alu_B[18] ,
    \riscv/alu_B[17] ,
    \riscv/alu_B[16] ,
    \riscv/alu_B[15] ,
    \riscv/alu_B[14] ,
    \riscv/alu_B[13] ,
    \riscv/alu_B[12] ,
    \riscv/alu_B[11] ,
    \riscv/alu_B[10] ,
    \riscv/alu_B[9] ,
    \riscv/alu_B[8] ,
    \riscv/alu_B[7] ,
    \riscv/alu_B[6] ,
    \riscv/alu_B[5] ,
    \riscv/alu_B[4] ,
    \riscv/alu_B[3] ,
    \riscv/alu_B[2] ,
    \riscv/alu_B[1] ,
    \riscv/alu_B[0] ,
    \riscv/alu_Result[31] ,
    \riscv/alu_Result[30] ,
    \riscv/alu_Result[29] ,
    \riscv/alu_Result[28] ,
    \riscv/alu_Result[27] ,
    \riscv/alu_Result[26] ,
    \riscv/alu_Result[25] ,
    \riscv/alu_Result[24] ,
    \riscv/alu_Result[23] ,
    \riscv/alu_Result[22] ,
    \riscv/alu_Result[21] ,
    \riscv/alu_Result[20] ,
    \riscv/alu_Result[19] ,
    \riscv/alu_Result[18] ,
    \riscv/alu_Result[17] ,
    \riscv/alu_Result[16] ,
    \riscv/alu_Result[15] ,
    \riscv/alu_Result[14] ,
    \riscv/alu_Result[13] ,
    \riscv/alu_Result[12] ,
    \riscv/alu_Result[11] ,
    \riscv/alu_Result[10] ,
    \riscv/alu_Result[9] ,
    \riscv/alu_Result[8] ,
    \riscv/alu_Result[7] ,
    \riscv/alu_Result[6] ,
    \riscv/alu_Result[5] ,
    \riscv/alu_Result[4] ,
    \riscv/alu_Result[3] ,
    \riscv/alu_Result[2] ,
    \riscv/alu_Result[1] ,
    \riscv/alu_Result[0] ,
    \riscv/ALUControl[2] ,
    \riscv/ALUControl[1] ,
    \riscv/ALUControl[0] ,
    \riscv/ALUSrc ,
    clk_p,
    \riscv/rst ,
    tms_pad_i,
    tck_pad_i,
    tdi_pad_i,
    tdo_pad_o
);

input \riscv/PC[31] ;
input \riscv/PC[30] ;
input \riscv/PC[29] ;
input \riscv/PC[28] ;
input \riscv/PC[27] ;
input \riscv/PC[26] ;
input \riscv/PC[25] ;
input \riscv/PC[24] ;
input \riscv/PC[23] ;
input \riscv/PC[22] ;
input \riscv/PC[21] ;
input \riscv/PC[20] ;
input \riscv/PC[19] ;
input \riscv/PC[18] ;
input \riscv/PC[17] ;
input \riscv/PC[16] ;
input \riscv/PC[15] ;
input \riscv/PC[14] ;
input \riscv/PC[13] ;
input \riscv/PC[12] ;
input \riscv/PC[11] ;
input \riscv/PC[10] ;
input \riscv/PC[9] ;
input \riscv/PC[8] ;
input \riscv/PC[7] ;
input \riscv/PC[6] ;
input \riscv/PC[5] ;
input \riscv/PC[4] ;
input \riscv/PC[3] ;
input \riscv/PC[2] ;
input \riscv/PC[1] ;
input \riscv/PC[0] ;
input \riscv/Instr[31] ;
input \riscv/Instr[30] ;
input \riscv/Instr[29] ;
input \riscv/Instr[28] ;
input \riscv/Instr[27] ;
input \riscv/Instr[26] ;
input \riscv/Instr[25] ;
input \riscv/Instr[24] ;
input \riscv/Instr[23] ;
input \riscv/Instr[22] ;
input \riscv/Instr[21] ;
input \riscv/Instr[20] ;
input \riscv/Instr[19] ;
input \riscv/Instr[18] ;
input \riscv/Instr[17] ;
input \riscv/Instr[16] ;
input \riscv/Instr[15] ;
input \riscv/Instr[14] ;
input \riscv/Instr[13] ;
input \riscv/Instr[12] ;
input \riscv/Instr[11] ;
input \riscv/Instr[10] ;
input \riscv/Instr[9] ;
input \riscv/Instr[8] ;
input \riscv/Instr[7] ;
input \riscv/Instr[6] ;
input \riscv/Instr[5] ;
input \riscv/Instr[4] ;
input \riscv/Instr[3] ;
input \riscv/Instr[2] ;
input \riscv/Instr[1] ;
input \riscv/Instr[0] ;
input \riscv/rf[2][31] ;
input \riscv/rf[2][30] ;
input \riscv/rf[2][29] ;
input \riscv/rf[2][28] ;
input \riscv/rf[2][27] ;
input \riscv/rf[2][26] ;
input \riscv/rf[2][25] ;
input \riscv/rf[2][24] ;
input \riscv/rf[2][23] ;
input \riscv/rf[2][22] ;
input \riscv/rf[2][21] ;
input \riscv/rf[2][20] ;
input \riscv/rf[2][19] ;
input \riscv/rf[2][18] ;
input \riscv/rf[2][17] ;
input \riscv/rf[2][16] ;
input \riscv/rf[2][15] ;
input \riscv/rf[2][14] ;
input \riscv/rf[2][13] ;
input \riscv/rf[2][12] ;
input \riscv/rf[2][11] ;
input \riscv/rf[2][10] ;
input \riscv/rf[2][9] ;
input \riscv/rf[2][8] ;
input \riscv/rf[2][7] ;
input \riscv/rf[2][6] ;
input \riscv/rf[2][5] ;
input \riscv/rf[2][4] ;
input \riscv/rf[2][3] ;
input \riscv/rf[2][2] ;
input \riscv/rf[2][1] ;
input \riscv/rf[2][0] ;
input \riscv/rf[3][31] ;
input \riscv/rf[3][30] ;
input \riscv/rf[3][29] ;
input \riscv/rf[3][28] ;
input \riscv/rf[3][27] ;
input \riscv/rf[3][26] ;
input \riscv/rf[3][25] ;
input \riscv/rf[3][24] ;
input \riscv/rf[3][23] ;
input \riscv/rf[3][22] ;
input \riscv/rf[3][21] ;
input \riscv/rf[3][20] ;
input \riscv/rf[3][19] ;
input \riscv/rf[3][18] ;
input \riscv/rf[3][17] ;
input \riscv/rf[3][16] ;
input \riscv/rf[3][15] ;
input \riscv/rf[3][14] ;
input \riscv/rf[3][13] ;
input \riscv/rf[3][12] ;
input \riscv/rf[3][11] ;
input \riscv/rf[3][10] ;
input \riscv/rf[3][9] ;
input \riscv/rf[3][8] ;
input \riscv/rf[3][7] ;
input \riscv/rf[3][6] ;
input \riscv/rf[3][5] ;
input \riscv/rf[3][4] ;
input \riscv/rf[3][3] ;
input \riscv/rf[3][2] ;
input \riscv/rf[3][1] ;
input \riscv/rf[3][0] ;
input \riscv/rf[7][31] ;
input \riscv/rf[7][30] ;
input \riscv/rf[7][29] ;
input \riscv/rf[7][28] ;
input \riscv/rf[7][27] ;
input \riscv/rf[7][26] ;
input \riscv/rf[7][25] ;
input \riscv/rf[7][24] ;
input \riscv/rf[7][23] ;
input \riscv/rf[7][22] ;
input \riscv/rf[7][21] ;
input \riscv/rf[7][20] ;
input \riscv/rf[7][19] ;
input \riscv/rf[7][18] ;
input \riscv/rf[7][17] ;
input \riscv/rf[7][16] ;
input \riscv/rf[7][15] ;
input \riscv/rf[7][14] ;
input \riscv/rf[7][13] ;
input \riscv/rf[7][12] ;
input \riscv/rf[7][11] ;
input \riscv/rf[7][10] ;
input \riscv/rf[7][9] ;
input \riscv/rf[7][8] ;
input \riscv/rf[7][7] ;
input \riscv/rf[7][6] ;
input \riscv/rf[7][5] ;
input \riscv/rf[7][4] ;
input \riscv/rf[7][3] ;
input \riscv/rf[7][2] ;
input \riscv/rf[7][1] ;
input \riscv/rf[7][0] ;
input \riscv/rf[4][31] ;
input \riscv/rf[4][30] ;
input \riscv/rf[4][29] ;
input \riscv/rf[4][28] ;
input \riscv/rf[4][27] ;
input \riscv/rf[4][26] ;
input \riscv/rf[4][25] ;
input \riscv/rf[4][24] ;
input \riscv/rf[4][23] ;
input \riscv/rf[4][22] ;
input \riscv/rf[4][21] ;
input \riscv/rf[4][20] ;
input \riscv/rf[4][19] ;
input \riscv/rf[4][18] ;
input \riscv/rf[4][17] ;
input \riscv/rf[4][16] ;
input \riscv/rf[4][15] ;
input \riscv/rf[4][14] ;
input \riscv/rf[4][13] ;
input \riscv/rf[4][12] ;
input \riscv/rf[4][11] ;
input \riscv/rf[4][10] ;
input \riscv/rf[4][9] ;
input \riscv/rf[4][8] ;
input \riscv/rf[4][7] ;
input \riscv/rf[4][6] ;
input \riscv/rf[4][5] ;
input \riscv/rf[4][4] ;
input \riscv/rf[4][3] ;
input \riscv/rf[4][2] ;
input \riscv/rf[4][1] ;
input \riscv/rf[4][0] ;
input \riscv/rf[5][31] ;
input \riscv/rf[5][30] ;
input \riscv/rf[5][29] ;
input \riscv/rf[5][28] ;
input \riscv/rf[5][27] ;
input \riscv/rf[5][26] ;
input \riscv/rf[5][25] ;
input \riscv/rf[5][24] ;
input \riscv/rf[5][23] ;
input \riscv/rf[5][22] ;
input \riscv/rf[5][21] ;
input \riscv/rf[5][20] ;
input \riscv/rf[5][19] ;
input \riscv/rf[5][18] ;
input \riscv/rf[5][17] ;
input \riscv/rf[5][16] ;
input \riscv/rf[5][15] ;
input \riscv/rf[5][14] ;
input \riscv/rf[5][13] ;
input \riscv/rf[5][12] ;
input \riscv/rf[5][11] ;
input \riscv/rf[5][10] ;
input \riscv/rf[5][9] ;
input \riscv/rf[5][8] ;
input \riscv/rf[5][7] ;
input \riscv/rf[5][6] ;
input \riscv/rf[5][5] ;
input \riscv/rf[5][4] ;
input \riscv/rf[5][3] ;
input \riscv/rf[5][2] ;
input \riscv/rf[5][1] ;
input \riscv/rf[5][0] ;
input \dmem/RAM[0][31] ;
input \dmem/RAM[0][30] ;
input \dmem/RAM[0][29] ;
input \dmem/RAM[0][28] ;
input \dmem/RAM[0][27] ;
input \dmem/RAM[0][26] ;
input \dmem/RAM[0][25] ;
input \dmem/RAM[0][24] ;
input \dmem/RAM[0][23] ;
input \dmem/RAM[0][22] ;
input \dmem/RAM[0][21] ;
input \dmem/RAM[0][20] ;
input \dmem/RAM[0][19] ;
input \dmem/RAM[0][18] ;
input \dmem/RAM[0][17] ;
input \dmem/RAM[0][16] ;
input \dmem/RAM[0][15] ;
input \dmem/RAM[0][14] ;
input \dmem/RAM[0][13] ;
input \dmem/RAM[0][12] ;
input \dmem/RAM[0][11] ;
input \dmem/RAM[0][10] ;
input \dmem/RAM[0][9] ;
input \dmem/RAM[0][8] ;
input \dmem/RAM[0][7] ;
input \dmem/RAM[0][6] ;
input \dmem/RAM[0][5] ;
input \dmem/RAM[0][4] ;
input \dmem/RAM[0][3] ;
input \dmem/RAM[0][2] ;
input \dmem/RAM[0][1] ;
input \dmem/RAM[0][0] ;
input \riscv/rf[9][31] ;
input \riscv/rf[9][30] ;
input \riscv/rf[9][29] ;
input \riscv/rf[9][28] ;
input \riscv/rf[9][27] ;
input \riscv/rf[9][26] ;
input \riscv/rf[9][25] ;
input \riscv/rf[9][24] ;
input \riscv/rf[9][23] ;
input \riscv/rf[9][22] ;
input \riscv/rf[9][21] ;
input \riscv/rf[9][20] ;
input \riscv/rf[9][19] ;
input \riscv/rf[9][18] ;
input \riscv/rf[9][17] ;
input \riscv/rf[9][16] ;
input \riscv/rf[9][15] ;
input \riscv/rf[9][14] ;
input \riscv/rf[9][13] ;
input \riscv/rf[9][12] ;
input \riscv/rf[9][11] ;
input \riscv/rf[9][10] ;
input \riscv/rf[9][9] ;
input \riscv/rf[9][8] ;
input \riscv/rf[9][7] ;
input \riscv/rf[9][6] ;
input \riscv/rf[9][5] ;
input \riscv/rf[9][4] ;
input \riscv/rf[9][3] ;
input \riscv/rf[9][2] ;
input \riscv/rf[9][1] ;
input \riscv/rf[9][0] ;
input \dmem/RAM[4][31] ;
input \dmem/RAM[4][30] ;
input \dmem/RAM[4][29] ;
input \dmem/RAM[4][28] ;
input \dmem/RAM[4][27] ;
input \dmem/RAM[4][26] ;
input \dmem/RAM[4][25] ;
input \dmem/RAM[4][24] ;
input \dmem/RAM[4][23] ;
input \dmem/RAM[4][22] ;
input \dmem/RAM[4][21] ;
input \dmem/RAM[4][20] ;
input \dmem/RAM[4][19] ;
input \dmem/RAM[4][18] ;
input \dmem/RAM[4][17] ;
input \dmem/RAM[4][16] ;
input \dmem/RAM[4][15] ;
input \dmem/RAM[4][14] ;
input \dmem/RAM[4][13] ;
input \dmem/RAM[4][12] ;
input \dmem/RAM[4][11] ;
input \dmem/RAM[4][10] ;
input \dmem/RAM[4][9] ;
input \dmem/RAM[4][8] ;
input \dmem/RAM[4][7] ;
input \dmem/RAM[4][6] ;
input \dmem/RAM[4][5] ;
input \dmem/RAM[4][4] ;
input \dmem/RAM[4][3] ;
input \dmem/RAM[4][2] ;
input \dmem/RAM[4][1] ;
input \dmem/RAM[4][0] ;
input \dmem/a[31] ;
input \dmem/a[30] ;
input \dmem/a[29] ;
input \dmem/a[28] ;
input \dmem/a[27] ;
input \dmem/a[26] ;
input \dmem/a[25] ;
input \dmem/a[24] ;
input \dmem/a[23] ;
input \dmem/a[22] ;
input \dmem/a[21] ;
input \dmem/a[20] ;
input \dmem/a[19] ;
input \dmem/a[18] ;
input \dmem/a[17] ;
input \dmem/a[16] ;
input \dmem/a[15] ;
input \dmem/a[14] ;
input \dmem/a[13] ;
input \dmem/a[12] ;
input \dmem/a[11] ;
input \dmem/a[10] ;
input \dmem/a[9] ;
input \dmem/a[8] ;
input \dmem/a[7] ;
input \dmem/a[6] ;
input \dmem/a[5] ;
input \dmem/a[4] ;
input \dmem/a[3] ;
input \dmem/a[2] ;
input \dmem/a[1] ;
input \dmem/a[0] ;
input \dmem/wd[31] ;
input \dmem/wd[30] ;
input \dmem/wd[29] ;
input \dmem/wd[28] ;
input \dmem/wd[27] ;
input \dmem/wd[26] ;
input \dmem/wd[25] ;
input \dmem/wd[24] ;
input \dmem/wd[23] ;
input \dmem/wd[22] ;
input \dmem/wd[21] ;
input \dmem/wd[20] ;
input \dmem/wd[19] ;
input \dmem/wd[18] ;
input \dmem/wd[17] ;
input \dmem/wd[16] ;
input \dmem/wd[15] ;
input \dmem/wd[14] ;
input \dmem/wd[13] ;
input \dmem/wd[12] ;
input \dmem/wd[11] ;
input \dmem/wd[10] ;
input \dmem/wd[9] ;
input \dmem/wd[8] ;
input \dmem/wd[7] ;
input \dmem/wd[6] ;
input \dmem/wd[5] ;
input \dmem/wd[4] ;
input \dmem/wd[3] ;
input \dmem/wd[2] ;
input \dmem/wd[1] ;
input \dmem/wd[0] ;
input \riscv/alu_A[31] ;
input \riscv/alu_A[30] ;
input \riscv/alu_A[29] ;
input \riscv/alu_A[28] ;
input \riscv/alu_A[27] ;
input \riscv/alu_A[26] ;
input \riscv/alu_A[25] ;
input \riscv/alu_A[24] ;
input \riscv/alu_A[23] ;
input \riscv/alu_A[22] ;
input \riscv/alu_A[21] ;
input \riscv/alu_A[20] ;
input \riscv/alu_A[19] ;
input \riscv/alu_A[18] ;
input \riscv/alu_A[17] ;
input \riscv/alu_A[16] ;
input \riscv/alu_A[15] ;
input \riscv/alu_A[14] ;
input \riscv/alu_A[13] ;
input \riscv/alu_A[12] ;
input \riscv/alu_A[11] ;
input \riscv/alu_A[10] ;
input \riscv/alu_A[9] ;
input \riscv/alu_A[8] ;
input \riscv/alu_A[7] ;
input \riscv/alu_A[6] ;
input \riscv/alu_A[5] ;
input \riscv/alu_A[4] ;
input \riscv/alu_A[3] ;
input \riscv/alu_A[2] ;
input \riscv/alu_A[1] ;
input \riscv/alu_A[0] ;
input \riscv/alu_B[31] ;
input \riscv/alu_B[30] ;
input \riscv/alu_B[29] ;
input \riscv/alu_B[28] ;
input \riscv/alu_B[27] ;
input \riscv/alu_B[26] ;
input \riscv/alu_B[25] ;
input \riscv/alu_B[24] ;
input \riscv/alu_B[23] ;
input \riscv/alu_B[22] ;
input \riscv/alu_B[21] ;
input \riscv/alu_B[20] ;
input \riscv/alu_B[19] ;
input \riscv/alu_B[18] ;
input \riscv/alu_B[17] ;
input \riscv/alu_B[16] ;
input \riscv/alu_B[15] ;
input \riscv/alu_B[14] ;
input \riscv/alu_B[13] ;
input \riscv/alu_B[12] ;
input \riscv/alu_B[11] ;
input \riscv/alu_B[10] ;
input \riscv/alu_B[9] ;
input \riscv/alu_B[8] ;
input \riscv/alu_B[7] ;
input \riscv/alu_B[6] ;
input \riscv/alu_B[5] ;
input \riscv/alu_B[4] ;
input \riscv/alu_B[3] ;
input \riscv/alu_B[2] ;
input \riscv/alu_B[1] ;
input \riscv/alu_B[0] ;
input \riscv/alu_Result[31] ;
input \riscv/alu_Result[30] ;
input \riscv/alu_Result[29] ;
input \riscv/alu_Result[28] ;
input \riscv/alu_Result[27] ;
input \riscv/alu_Result[26] ;
input \riscv/alu_Result[25] ;
input \riscv/alu_Result[24] ;
input \riscv/alu_Result[23] ;
input \riscv/alu_Result[22] ;
input \riscv/alu_Result[21] ;
input \riscv/alu_Result[20] ;
input \riscv/alu_Result[19] ;
input \riscv/alu_Result[18] ;
input \riscv/alu_Result[17] ;
input \riscv/alu_Result[16] ;
input \riscv/alu_Result[15] ;
input \riscv/alu_Result[14] ;
input \riscv/alu_Result[13] ;
input \riscv/alu_Result[12] ;
input \riscv/alu_Result[11] ;
input \riscv/alu_Result[10] ;
input \riscv/alu_Result[9] ;
input \riscv/alu_Result[8] ;
input \riscv/alu_Result[7] ;
input \riscv/alu_Result[6] ;
input \riscv/alu_Result[5] ;
input \riscv/alu_Result[4] ;
input \riscv/alu_Result[3] ;
input \riscv/alu_Result[2] ;
input \riscv/alu_Result[1] ;
input \riscv/alu_Result[0] ;
input \riscv/ALUControl[2] ;
input \riscv/ALUControl[1] ;
input \riscv/ALUControl[0] ;
input \riscv/ALUSrc ;
input clk_p;
input \riscv/rst ;
input tms_pad_i;
input tck_pad_i;
input tdi_pad_i;
output tdo_pad_o;

wire \riscv/PC[31] ;
wire \riscv/PC[30] ;
wire \riscv/PC[29] ;
wire \riscv/PC[28] ;
wire \riscv/PC[27] ;
wire \riscv/PC[26] ;
wire \riscv/PC[25] ;
wire \riscv/PC[24] ;
wire \riscv/PC[23] ;
wire \riscv/PC[22] ;
wire \riscv/PC[21] ;
wire \riscv/PC[20] ;
wire \riscv/PC[19] ;
wire \riscv/PC[18] ;
wire \riscv/PC[17] ;
wire \riscv/PC[16] ;
wire \riscv/PC[15] ;
wire \riscv/PC[14] ;
wire \riscv/PC[13] ;
wire \riscv/PC[12] ;
wire \riscv/PC[11] ;
wire \riscv/PC[10] ;
wire \riscv/PC[9] ;
wire \riscv/PC[8] ;
wire \riscv/PC[7] ;
wire \riscv/PC[6] ;
wire \riscv/PC[5] ;
wire \riscv/PC[4] ;
wire \riscv/PC[3] ;
wire \riscv/PC[2] ;
wire \riscv/PC[1] ;
wire \riscv/PC[0] ;
wire \riscv/Instr[31] ;
wire \riscv/Instr[30] ;
wire \riscv/Instr[29] ;
wire \riscv/Instr[28] ;
wire \riscv/Instr[27] ;
wire \riscv/Instr[26] ;
wire \riscv/Instr[25] ;
wire \riscv/Instr[24] ;
wire \riscv/Instr[23] ;
wire \riscv/Instr[22] ;
wire \riscv/Instr[21] ;
wire \riscv/Instr[20] ;
wire \riscv/Instr[19] ;
wire \riscv/Instr[18] ;
wire \riscv/Instr[17] ;
wire \riscv/Instr[16] ;
wire \riscv/Instr[15] ;
wire \riscv/Instr[14] ;
wire \riscv/Instr[13] ;
wire \riscv/Instr[12] ;
wire \riscv/Instr[11] ;
wire \riscv/Instr[10] ;
wire \riscv/Instr[9] ;
wire \riscv/Instr[8] ;
wire \riscv/Instr[7] ;
wire \riscv/Instr[6] ;
wire \riscv/Instr[5] ;
wire \riscv/Instr[4] ;
wire \riscv/Instr[3] ;
wire \riscv/Instr[2] ;
wire \riscv/Instr[1] ;
wire \riscv/Instr[0] ;
wire \riscv/rf[2][31] ;
wire \riscv/rf[2][30] ;
wire \riscv/rf[2][29] ;
wire \riscv/rf[2][28] ;
wire \riscv/rf[2][27] ;
wire \riscv/rf[2][26] ;
wire \riscv/rf[2][25] ;
wire \riscv/rf[2][24] ;
wire \riscv/rf[2][23] ;
wire \riscv/rf[2][22] ;
wire \riscv/rf[2][21] ;
wire \riscv/rf[2][20] ;
wire \riscv/rf[2][19] ;
wire \riscv/rf[2][18] ;
wire \riscv/rf[2][17] ;
wire \riscv/rf[2][16] ;
wire \riscv/rf[2][15] ;
wire \riscv/rf[2][14] ;
wire \riscv/rf[2][13] ;
wire \riscv/rf[2][12] ;
wire \riscv/rf[2][11] ;
wire \riscv/rf[2][10] ;
wire \riscv/rf[2][9] ;
wire \riscv/rf[2][8] ;
wire \riscv/rf[2][7] ;
wire \riscv/rf[2][6] ;
wire \riscv/rf[2][5] ;
wire \riscv/rf[2][4] ;
wire \riscv/rf[2][3] ;
wire \riscv/rf[2][2] ;
wire \riscv/rf[2][1] ;
wire \riscv/rf[2][0] ;
wire \riscv/rf[3][31] ;
wire \riscv/rf[3][30] ;
wire \riscv/rf[3][29] ;
wire \riscv/rf[3][28] ;
wire \riscv/rf[3][27] ;
wire \riscv/rf[3][26] ;
wire \riscv/rf[3][25] ;
wire \riscv/rf[3][24] ;
wire \riscv/rf[3][23] ;
wire \riscv/rf[3][22] ;
wire \riscv/rf[3][21] ;
wire \riscv/rf[3][20] ;
wire \riscv/rf[3][19] ;
wire \riscv/rf[3][18] ;
wire \riscv/rf[3][17] ;
wire \riscv/rf[3][16] ;
wire \riscv/rf[3][15] ;
wire \riscv/rf[3][14] ;
wire \riscv/rf[3][13] ;
wire \riscv/rf[3][12] ;
wire \riscv/rf[3][11] ;
wire \riscv/rf[3][10] ;
wire \riscv/rf[3][9] ;
wire \riscv/rf[3][8] ;
wire \riscv/rf[3][7] ;
wire \riscv/rf[3][6] ;
wire \riscv/rf[3][5] ;
wire \riscv/rf[3][4] ;
wire \riscv/rf[3][3] ;
wire \riscv/rf[3][2] ;
wire \riscv/rf[3][1] ;
wire \riscv/rf[3][0] ;
wire \riscv/rf[7][31] ;
wire \riscv/rf[7][30] ;
wire \riscv/rf[7][29] ;
wire \riscv/rf[7][28] ;
wire \riscv/rf[7][27] ;
wire \riscv/rf[7][26] ;
wire \riscv/rf[7][25] ;
wire \riscv/rf[7][24] ;
wire \riscv/rf[7][23] ;
wire \riscv/rf[7][22] ;
wire \riscv/rf[7][21] ;
wire \riscv/rf[7][20] ;
wire \riscv/rf[7][19] ;
wire \riscv/rf[7][18] ;
wire \riscv/rf[7][17] ;
wire \riscv/rf[7][16] ;
wire \riscv/rf[7][15] ;
wire \riscv/rf[7][14] ;
wire \riscv/rf[7][13] ;
wire \riscv/rf[7][12] ;
wire \riscv/rf[7][11] ;
wire \riscv/rf[7][10] ;
wire \riscv/rf[7][9] ;
wire \riscv/rf[7][8] ;
wire \riscv/rf[7][7] ;
wire \riscv/rf[7][6] ;
wire \riscv/rf[7][5] ;
wire \riscv/rf[7][4] ;
wire \riscv/rf[7][3] ;
wire \riscv/rf[7][2] ;
wire \riscv/rf[7][1] ;
wire \riscv/rf[7][0] ;
wire \riscv/rf[4][31] ;
wire \riscv/rf[4][30] ;
wire \riscv/rf[4][29] ;
wire \riscv/rf[4][28] ;
wire \riscv/rf[4][27] ;
wire \riscv/rf[4][26] ;
wire \riscv/rf[4][25] ;
wire \riscv/rf[4][24] ;
wire \riscv/rf[4][23] ;
wire \riscv/rf[4][22] ;
wire \riscv/rf[4][21] ;
wire \riscv/rf[4][20] ;
wire \riscv/rf[4][19] ;
wire \riscv/rf[4][18] ;
wire \riscv/rf[4][17] ;
wire \riscv/rf[4][16] ;
wire \riscv/rf[4][15] ;
wire \riscv/rf[4][14] ;
wire \riscv/rf[4][13] ;
wire \riscv/rf[4][12] ;
wire \riscv/rf[4][11] ;
wire \riscv/rf[4][10] ;
wire \riscv/rf[4][9] ;
wire \riscv/rf[4][8] ;
wire \riscv/rf[4][7] ;
wire \riscv/rf[4][6] ;
wire \riscv/rf[4][5] ;
wire \riscv/rf[4][4] ;
wire \riscv/rf[4][3] ;
wire \riscv/rf[4][2] ;
wire \riscv/rf[4][1] ;
wire \riscv/rf[4][0] ;
wire \riscv/rf[5][31] ;
wire \riscv/rf[5][30] ;
wire \riscv/rf[5][29] ;
wire \riscv/rf[5][28] ;
wire \riscv/rf[5][27] ;
wire \riscv/rf[5][26] ;
wire \riscv/rf[5][25] ;
wire \riscv/rf[5][24] ;
wire \riscv/rf[5][23] ;
wire \riscv/rf[5][22] ;
wire \riscv/rf[5][21] ;
wire \riscv/rf[5][20] ;
wire \riscv/rf[5][19] ;
wire \riscv/rf[5][18] ;
wire \riscv/rf[5][17] ;
wire \riscv/rf[5][16] ;
wire \riscv/rf[5][15] ;
wire \riscv/rf[5][14] ;
wire \riscv/rf[5][13] ;
wire \riscv/rf[5][12] ;
wire \riscv/rf[5][11] ;
wire \riscv/rf[5][10] ;
wire \riscv/rf[5][9] ;
wire \riscv/rf[5][8] ;
wire \riscv/rf[5][7] ;
wire \riscv/rf[5][6] ;
wire \riscv/rf[5][5] ;
wire \riscv/rf[5][4] ;
wire \riscv/rf[5][3] ;
wire \riscv/rf[5][2] ;
wire \riscv/rf[5][1] ;
wire \riscv/rf[5][0] ;
wire \dmem/RAM[0][31] ;
wire \dmem/RAM[0][30] ;
wire \dmem/RAM[0][29] ;
wire \dmem/RAM[0][28] ;
wire \dmem/RAM[0][27] ;
wire \dmem/RAM[0][26] ;
wire \dmem/RAM[0][25] ;
wire \dmem/RAM[0][24] ;
wire \dmem/RAM[0][23] ;
wire \dmem/RAM[0][22] ;
wire \dmem/RAM[0][21] ;
wire \dmem/RAM[0][20] ;
wire \dmem/RAM[0][19] ;
wire \dmem/RAM[0][18] ;
wire \dmem/RAM[0][17] ;
wire \dmem/RAM[0][16] ;
wire \dmem/RAM[0][15] ;
wire \dmem/RAM[0][14] ;
wire \dmem/RAM[0][13] ;
wire \dmem/RAM[0][12] ;
wire \dmem/RAM[0][11] ;
wire \dmem/RAM[0][10] ;
wire \dmem/RAM[0][9] ;
wire \dmem/RAM[0][8] ;
wire \dmem/RAM[0][7] ;
wire \dmem/RAM[0][6] ;
wire \dmem/RAM[0][5] ;
wire \dmem/RAM[0][4] ;
wire \dmem/RAM[0][3] ;
wire \dmem/RAM[0][2] ;
wire \dmem/RAM[0][1] ;
wire \dmem/RAM[0][0] ;
wire \riscv/rf[9][31] ;
wire \riscv/rf[9][30] ;
wire \riscv/rf[9][29] ;
wire \riscv/rf[9][28] ;
wire \riscv/rf[9][27] ;
wire \riscv/rf[9][26] ;
wire \riscv/rf[9][25] ;
wire \riscv/rf[9][24] ;
wire \riscv/rf[9][23] ;
wire \riscv/rf[9][22] ;
wire \riscv/rf[9][21] ;
wire \riscv/rf[9][20] ;
wire \riscv/rf[9][19] ;
wire \riscv/rf[9][18] ;
wire \riscv/rf[9][17] ;
wire \riscv/rf[9][16] ;
wire \riscv/rf[9][15] ;
wire \riscv/rf[9][14] ;
wire \riscv/rf[9][13] ;
wire \riscv/rf[9][12] ;
wire \riscv/rf[9][11] ;
wire \riscv/rf[9][10] ;
wire \riscv/rf[9][9] ;
wire \riscv/rf[9][8] ;
wire \riscv/rf[9][7] ;
wire \riscv/rf[9][6] ;
wire \riscv/rf[9][5] ;
wire \riscv/rf[9][4] ;
wire \riscv/rf[9][3] ;
wire \riscv/rf[9][2] ;
wire \riscv/rf[9][1] ;
wire \riscv/rf[9][0] ;
wire \dmem/RAM[4][31] ;
wire \dmem/RAM[4][30] ;
wire \dmem/RAM[4][29] ;
wire \dmem/RAM[4][28] ;
wire \dmem/RAM[4][27] ;
wire \dmem/RAM[4][26] ;
wire \dmem/RAM[4][25] ;
wire \dmem/RAM[4][24] ;
wire \dmem/RAM[4][23] ;
wire \dmem/RAM[4][22] ;
wire \dmem/RAM[4][21] ;
wire \dmem/RAM[4][20] ;
wire \dmem/RAM[4][19] ;
wire \dmem/RAM[4][18] ;
wire \dmem/RAM[4][17] ;
wire \dmem/RAM[4][16] ;
wire \dmem/RAM[4][15] ;
wire \dmem/RAM[4][14] ;
wire \dmem/RAM[4][13] ;
wire \dmem/RAM[4][12] ;
wire \dmem/RAM[4][11] ;
wire \dmem/RAM[4][10] ;
wire \dmem/RAM[4][9] ;
wire \dmem/RAM[4][8] ;
wire \dmem/RAM[4][7] ;
wire \dmem/RAM[4][6] ;
wire \dmem/RAM[4][5] ;
wire \dmem/RAM[4][4] ;
wire \dmem/RAM[4][3] ;
wire \dmem/RAM[4][2] ;
wire \dmem/RAM[4][1] ;
wire \dmem/RAM[4][0] ;
wire \dmem/a[31] ;
wire \dmem/a[30] ;
wire \dmem/a[29] ;
wire \dmem/a[28] ;
wire \dmem/a[27] ;
wire \dmem/a[26] ;
wire \dmem/a[25] ;
wire \dmem/a[24] ;
wire \dmem/a[23] ;
wire \dmem/a[22] ;
wire \dmem/a[21] ;
wire \dmem/a[20] ;
wire \dmem/a[19] ;
wire \dmem/a[18] ;
wire \dmem/a[17] ;
wire \dmem/a[16] ;
wire \dmem/a[15] ;
wire \dmem/a[14] ;
wire \dmem/a[13] ;
wire \dmem/a[12] ;
wire \dmem/a[11] ;
wire \dmem/a[10] ;
wire \dmem/a[9] ;
wire \dmem/a[8] ;
wire \dmem/a[7] ;
wire \dmem/a[6] ;
wire \dmem/a[5] ;
wire \dmem/a[4] ;
wire \dmem/a[3] ;
wire \dmem/a[2] ;
wire \dmem/a[1] ;
wire \dmem/a[0] ;
wire \dmem/wd[31] ;
wire \dmem/wd[30] ;
wire \dmem/wd[29] ;
wire \dmem/wd[28] ;
wire \dmem/wd[27] ;
wire \dmem/wd[26] ;
wire \dmem/wd[25] ;
wire \dmem/wd[24] ;
wire \dmem/wd[23] ;
wire \dmem/wd[22] ;
wire \dmem/wd[21] ;
wire \dmem/wd[20] ;
wire \dmem/wd[19] ;
wire \dmem/wd[18] ;
wire \dmem/wd[17] ;
wire \dmem/wd[16] ;
wire \dmem/wd[15] ;
wire \dmem/wd[14] ;
wire \dmem/wd[13] ;
wire \dmem/wd[12] ;
wire \dmem/wd[11] ;
wire \dmem/wd[10] ;
wire \dmem/wd[9] ;
wire \dmem/wd[8] ;
wire \dmem/wd[7] ;
wire \dmem/wd[6] ;
wire \dmem/wd[5] ;
wire \dmem/wd[4] ;
wire \dmem/wd[3] ;
wire \dmem/wd[2] ;
wire \dmem/wd[1] ;
wire \dmem/wd[0] ;
wire \riscv/alu_A[31] ;
wire \riscv/alu_A[30] ;
wire \riscv/alu_A[29] ;
wire \riscv/alu_A[28] ;
wire \riscv/alu_A[27] ;
wire \riscv/alu_A[26] ;
wire \riscv/alu_A[25] ;
wire \riscv/alu_A[24] ;
wire \riscv/alu_A[23] ;
wire \riscv/alu_A[22] ;
wire \riscv/alu_A[21] ;
wire \riscv/alu_A[20] ;
wire \riscv/alu_A[19] ;
wire \riscv/alu_A[18] ;
wire \riscv/alu_A[17] ;
wire \riscv/alu_A[16] ;
wire \riscv/alu_A[15] ;
wire \riscv/alu_A[14] ;
wire \riscv/alu_A[13] ;
wire \riscv/alu_A[12] ;
wire \riscv/alu_A[11] ;
wire \riscv/alu_A[10] ;
wire \riscv/alu_A[9] ;
wire \riscv/alu_A[8] ;
wire \riscv/alu_A[7] ;
wire \riscv/alu_A[6] ;
wire \riscv/alu_A[5] ;
wire \riscv/alu_A[4] ;
wire \riscv/alu_A[3] ;
wire \riscv/alu_A[2] ;
wire \riscv/alu_A[1] ;
wire \riscv/alu_A[0] ;
wire \riscv/alu_B[31] ;
wire \riscv/alu_B[30] ;
wire \riscv/alu_B[29] ;
wire \riscv/alu_B[28] ;
wire \riscv/alu_B[27] ;
wire \riscv/alu_B[26] ;
wire \riscv/alu_B[25] ;
wire \riscv/alu_B[24] ;
wire \riscv/alu_B[23] ;
wire \riscv/alu_B[22] ;
wire \riscv/alu_B[21] ;
wire \riscv/alu_B[20] ;
wire \riscv/alu_B[19] ;
wire \riscv/alu_B[18] ;
wire \riscv/alu_B[17] ;
wire \riscv/alu_B[16] ;
wire \riscv/alu_B[15] ;
wire \riscv/alu_B[14] ;
wire \riscv/alu_B[13] ;
wire \riscv/alu_B[12] ;
wire \riscv/alu_B[11] ;
wire \riscv/alu_B[10] ;
wire \riscv/alu_B[9] ;
wire \riscv/alu_B[8] ;
wire \riscv/alu_B[7] ;
wire \riscv/alu_B[6] ;
wire \riscv/alu_B[5] ;
wire \riscv/alu_B[4] ;
wire \riscv/alu_B[3] ;
wire \riscv/alu_B[2] ;
wire \riscv/alu_B[1] ;
wire \riscv/alu_B[0] ;
wire \riscv/alu_Result[31] ;
wire \riscv/alu_Result[30] ;
wire \riscv/alu_Result[29] ;
wire \riscv/alu_Result[28] ;
wire \riscv/alu_Result[27] ;
wire \riscv/alu_Result[26] ;
wire \riscv/alu_Result[25] ;
wire \riscv/alu_Result[24] ;
wire \riscv/alu_Result[23] ;
wire \riscv/alu_Result[22] ;
wire \riscv/alu_Result[21] ;
wire \riscv/alu_Result[20] ;
wire \riscv/alu_Result[19] ;
wire \riscv/alu_Result[18] ;
wire \riscv/alu_Result[17] ;
wire \riscv/alu_Result[16] ;
wire \riscv/alu_Result[15] ;
wire \riscv/alu_Result[14] ;
wire \riscv/alu_Result[13] ;
wire \riscv/alu_Result[12] ;
wire \riscv/alu_Result[11] ;
wire \riscv/alu_Result[10] ;
wire \riscv/alu_Result[9] ;
wire \riscv/alu_Result[8] ;
wire \riscv/alu_Result[7] ;
wire \riscv/alu_Result[6] ;
wire \riscv/alu_Result[5] ;
wire \riscv/alu_Result[4] ;
wire \riscv/alu_Result[3] ;
wire \riscv/alu_Result[2] ;
wire \riscv/alu_Result[1] ;
wire \riscv/alu_Result[0] ;
wire \riscv/ALUControl[2] ;
wire \riscv/ALUControl[1] ;
wire \riscv/ALUControl[0] ;
wire \riscv/ALUSrc ;
wire clk_p;
wire \riscv/rst ;
wire tms_pad_i;
wire tck_pad_i;
wire tdi_pad_i;
wire tdo_pad_o;
wire tms_i_c;
wire tck_i_c;
wire tdi_i_c;
wire tdo_o_c;
wire [9:0] control0;
wire gao_jtag_tck;
wire gao_jtag_reset;
wire run_test_idle_er1;
wire run_test_idle_er2;
wire shift_dr_capture_dr;
wire update_dr;
wire pause_dr;
wire enable_er1;
wire enable_er2;
wire gao_jtag_tdi;
wire tdo_er1;

IBUF tms_ibuf (
    .I(tms_pad_i),
    .O(tms_i_c)
);

IBUF tck_ibuf (
    .I(tck_pad_i),
    .O(tck_i_c)
);

IBUF tdi_ibuf (
    .I(tdi_pad_i),
    .O(tdi_i_c)
);

OBUF tdo_obuf (
    .I(tdo_o_c),
    .O(tdo_pad_o)
);

GW_JTAG  u_gw_jtag(
    .tms_pad_i(tms_i_c),
    .tck_pad_i(tck_i_c),
    .tdi_pad_i(tdi_i_c),
    .tdo_pad_o(tdo_o_c),
    .tck_o(gao_jtag_tck),
    .test_logic_reset_o(gao_jtag_reset),
    .run_test_idle_er1_o(run_test_idle_er1),
    .run_test_idle_er2_o(run_test_idle_er2),
    .shift_dr_capture_dr_o(shift_dr_capture_dr),
    .update_dr_o(update_dr),
    .pause_dr_o(pause_dr),
    .enable_er1_o(enable_er1),
    .enable_er2_o(enable_er2),
    .tdi_o(gao_jtag_tdi),
    .tdo_er1_i(tdo_er1),
    .tdo_er2_i(1'b0)
);

gw_con_top  u_icon_top(
    .tck_i(gao_jtag_tck),
    .tdi_i(gao_jtag_tdi),
    .tdo_o(tdo_er1),
    .rst_i(gao_jtag_reset),
    .control0(control0[9:0]),
    .enable_i(enable_er1),
    .shift_dr_capture_dr_i(shift_dr_capture_dr),
    .update_dr_i(update_dr)
);

ao_top_0  u_la0_top(
    .control(control0[9:0]),
    .trig0_i(\riscv/rst ),
    .trig1_i({\riscv/PC[31] ,\riscv/PC[30] ,\riscv/PC[29] ,\riscv/PC[28] ,\riscv/PC[27] ,\riscv/PC[26] ,\riscv/PC[25] ,\riscv/PC[24] ,\riscv/PC[23] ,\riscv/PC[22] ,\riscv/PC[21] ,\riscv/PC[20] ,\riscv/PC[19] ,\riscv/PC[18] ,\riscv/PC[17] ,\riscv/PC[16] ,\riscv/PC[15] ,\riscv/PC[14] ,\riscv/PC[13] ,\riscv/PC[12] ,\riscv/PC[11] ,\riscv/PC[10] ,\riscv/PC[9] ,\riscv/PC[8] ,\riscv/PC[7] ,\riscv/PC[6] ,\riscv/PC[5] ,\riscv/PC[4] ,\riscv/PC[3] ,\riscv/PC[2] ,\riscv/PC[1] ,\riscv/PC[0] }),
    .data_i({\riscv/PC[31] ,\riscv/PC[30] ,\riscv/PC[29] ,\riscv/PC[28] ,\riscv/PC[27] ,\riscv/PC[26] ,\riscv/PC[25] ,\riscv/PC[24] ,\riscv/PC[23] ,\riscv/PC[22] ,\riscv/PC[21] ,\riscv/PC[20] ,\riscv/PC[19] ,\riscv/PC[18] ,\riscv/PC[17] ,\riscv/PC[16] ,\riscv/PC[15] ,\riscv/PC[14] ,\riscv/PC[13] ,\riscv/PC[12] ,\riscv/PC[11] ,\riscv/PC[10] ,\riscv/PC[9] ,\riscv/PC[8] ,\riscv/PC[7] ,\riscv/PC[6] ,\riscv/PC[5] ,\riscv/PC[4] ,\riscv/PC[3] ,\riscv/PC[2] ,\riscv/PC[1] ,\riscv/PC[0] ,\riscv/Instr[31] ,\riscv/Instr[30] ,\riscv/Instr[29] ,\riscv/Instr[28] ,\riscv/Instr[27] ,\riscv/Instr[26] ,\riscv/Instr[25] ,\riscv/Instr[24] ,\riscv/Instr[23] ,\riscv/Instr[22] ,\riscv/Instr[21] ,\riscv/Instr[20] ,\riscv/Instr[19] ,\riscv/Instr[18] ,\riscv/Instr[17] ,\riscv/Instr[16] ,\riscv/Instr[15] ,\riscv/Instr[14] ,\riscv/Instr[13] ,\riscv/Instr[12] ,\riscv/Instr[11] ,\riscv/Instr[10] ,\riscv/Instr[9] ,\riscv/Instr[8] ,\riscv/Instr[7] ,\riscv/Instr[6] ,\riscv/Instr[5] ,\riscv/Instr[4] ,\riscv/Instr[3] ,\riscv/Instr[2] ,\riscv/Instr[1] ,\riscv/Instr[0] ,\riscv/rf[2][31] ,\riscv/rf[2][30] ,\riscv/rf[2][29] ,\riscv/rf[2][28] ,\riscv/rf[2][27] ,\riscv/rf[2][26] ,\riscv/rf[2][25] ,\riscv/rf[2][24] ,\riscv/rf[2][23] ,\riscv/rf[2][22] ,\riscv/rf[2][21] ,\riscv/rf[2][20] ,\riscv/rf[2][19] ,\riscv/rf[2][18] ,\riscv/rf[2][17] ,\riscv/rf[2][16] ,\riscv/rf[2][15] ,\riscv/rf[2][14] ,\riscv/rf[2][13] ,\riscv/rf[2][12] ,\riscv/rf[2][11] ,\riscv/rf[2][10] ,\riscv/rf[2][9] ,\riscv/rf[2][8] ,\riscv/rf[2][7] ,\riscv/rf[2][6] ,\riscv/rf[2][5] ,\riscv/rf[2][4] ,\riscv/rf[2][3] ,\riscv/rf[2][2] ,\riscv/rf[2][1] ,\riscv/rf[2][0] ,\riscv/rf[3][31] ,\riscv/rf[3][30] ,\riscv/rf[3][29] ,\riscv/rf[3][28] ,\riscv/rf[3][27] ,\riscv/rf[3][26] ,\riscv/rf[3][25] ,\riscv/rf[3][24] ,\riscv/rf[3][23] ,\riscv/rf[3][22] ,\riscv/rf[3][21] ,\riscv/rf[3][20] ,\riscv/rf[3][19] ,\riscv/rf[3][18] ,\riscv/rf[3][17] ,\riscv/rf[3][16] ,\riscv/rf[3][15] ,\riscv/rf[3][14] ,\riscv/rf[3][13] ,\riscv/rf[3][12] ,\riscv/rf[3][11] ,\riscv/rf[3][10] ,\riscv/rf[3][9] ,\riscv/rf[3][8] ,\riscv/rf[3][7] ,\riscv/rf[3][6] ,\riscv/rf[3][5] ,\riscv/rf[3][4] ,\riscv/rf[3][3] ,\riscv/rf[3][2] ,\riscv/rf[3][1] ,\riscv/rf[3][0] ,\riscv/rf[7][31] ,\riscv/rf[7][30] ,\riscv/rf[7][29] ,\riscv/rf[7][28] ,\riscv/rf[7][27] ,\riscv/rf[7][26] ,\riscv/rf[7][25] ,\riscv/rf[7][24] ,\riscv/rf[7][23] ,\riscv/rf[7][22] ,\riscv/rf[7][21] ,\riscv/rf[7][20] ,\riscv/rf[7][19] ,\riscv/rf[7][18] ,\riscv/rf[7][17] ,\riscv/rf[7][16] ,\riscv/rf[7][15] ,\riscv/rf[7][14] ,\riscv/rf[7][13] ,\riscv/rf[7][12] ,\riscv/rf[7][11] ,\riscv/rf[7][10] ,\riscv/rf[7][9] ,\riscv/rf[7][8] ,\riscv/rf[7][7] ,\riscv/rf[7][6] ,\riscv/rf[7][5] ,\riscv/rf[7][4] ,\riscv/rf[7][3] ,\riscv/rf[7][2] ,\riscv/rf[7][1] ,\riscv/rf[7][0] ,\riscv/rf[4][31] ,\riscv/rf[4][30] ,\riscv/rf[4][29] ,\riscv/rf[4][28] ,\riscv/rf[4][27] ,\riscv/rf[4][26] ,\riscv/rf[4][25] ,\riscv/rf[4][24] ,\riscv/rf[4][23] ,\riscv/rf[4][22] ,\riscv/rf[4][21] ,\riscv/rf[4][20] ,\riscv/rf[4][19] ,\riscv/rf[4][18] ,\riscv/rf[4][17] ,\riscv/rf[4][16] ,\riscv/rf[4][15] ,\riscv/rf[4][14] ,\riscv/rf[4][13] ,\riscv/rf[4][12] ,\riscv/rf[4][11] ,\riscv/rf[4][10] ,\riscv/rf[4][9] ,\riscv/rf[4][8] ,\riscv/rf[4][7] ,\riscv/rf[4][6] ,\riscv/rf[4][5] ,\riscv/rf[4][4] ,\riscv/rf[4][3] ,\riscv/rf[4][2] ,\riscv/rf[4][1] ,\riscv/rf[4][0] ,\riscv/rf[5][31] ,\riscv/rf[5][30] ,\riscv/rf[5][29] ,\riscv/rf[5][28] ,\riscv/rf[5][27] ,\riscv/rf[5][26] ,\riscv/rf[5][25] ,\riscv/rf[5][24] ,\riscv/rf[5][23] ,\riscv/rf[5][22] ,\riscv/rf[5][21] ,\riscv/rf[5][20] ,\riscv/rf[5][19] ,\riscv/rf[5][18] ,\riscv/rf[5][17] ,\riscv/rf[5][16] ,\riscv/rf[5][15] ,\riscv/rf[5][14] ,\riscv/rf[5][13] ,\riscv/rf[5][12] ,\riscv/rf[5][11] ,\riscv/rf[5][10] ,\riscv/rf[5][9] ,\riscv/rf[5][8] ,\riscv/rf[5][7] ,\riscv/rf[5][6] ,\riscv/rf[5][5] ,\riscv/rf[5][4] ,\riscv/rf[5][3] ,\riscv/rf[5][2] ,\riscv/rf[5][1] ,\riscv/rf[5][0] ,\dmem/RAM[0][31] ,\dmem/RAM[0][30] ,\dmem/RAM[0][29] ,\dmem/RAM[0][28] ,\dmem/RAM[0][27] ,\dmem/RAM[0][26] ,\dmem/RAM[0][25] ,\dmem/RAM[0][24] ,\dmem/RAM[0][23] ,\dmem/RAM[0][22] ,\dmem/RAM[0][21] ,\dmem/RAM[0][20] ,\dmem/RAM[0][19] ,\dmem/RAM[0][18] ,\dmem/RAM[0][17] ,\dmem/RAM[0][16] ,\dmem/RAM[0][15] ,\dmem/RAM[0][14] ,\dmem/RAM[0][13] ,\dmem/RAM[0][12] ,\dmem/RAM[0][11] ,\dmem/RAM[0][10] ,\dmem/RAM[0][9] ,\dmem/RAM[0][8] ,\dmem/RAM[0][7] ,\dmem/RAM[0][6] ,\dmem/RAM[0][5] ,\dmem/RAM[0][4] ,\dmem/RAM[0][3] ,\dmem/RAM[0][2] ,\dmem/RAM[0][1] ,\dmem/RAM[0][0] ,\riscv/rf[9][31] ,\riscv/rf[9][30] ,\riscv/rf[9][29] ,\riscv/rf[9][28] ,\riscv/rf[9][27] ,\riscv/rf[9][26] ,\riscv/rf[9][25] ,\riscv/rf[9][24] ,\riscv/rf[9][23] ,\riscv/rf[9][22] ,\riscv/rf[9][21] ,\riscv/rf[9][20] ,\riscv/rf[9][19] ,\riscv/rf[9][18] ,\riscv/rf[9][17] ,\riscv/rf[9][16] ,\riscv/rf[9][15] ,\riscv/rf[9][14] ,\riscv/rf[9][13] ,\riscv/rf[9][12] ,\riscv/rf[9][11] ,\riscv/rf[9][10] ,\riscv/rf[9][9] ,\riscv/rf[9][8] ,\riscv/rf[9][7] ,\riscv/rf[9][6] ,\riscv/rf[9][5] ,\riscv/rf[9][4] ,\riscv/rf[9][3] ,\riscv/rf[9][2] ,\riscv/rf[9][1] ,\riscv/rf[9][0] ,\dmem/RAM[4][31] ,\dmem/RAM[4][30] ,\dmem/RAM[4][29] ,\dmem/RAM[4][28] ,\dmem/RAM[4][27] ,\dmem/RAM[4][26] ,\dmem/RAM[4][25] ,\dmem/RAM[4][24] ,\dmem/RAM[4][23] ,\dmem/RAM[4][22] ,\dmem/RAM[4][21] ,\dmem/RAM[4][20] ,\dmem/RAM[4][19] ,\dmem/RAM[4][18] ,\dmem/RAM[4][17] ,\dmem/RAM[4][16] ,\dmem/RAM[4][15] ,\dmem/RAM[4][14] ,\dmem/RAM[4][13] ,\dmem/RAM[4][12] ,\dmem/RAM[4][11] ,\dmem/RAM[4][10] ,\dmem/RAM[4][9] ,\dmem/RAM[4][8] ,\dmem/RAM[4][7] ,\dmem/RAM[4][6] ,\dmem/RAM[4][5] ,\dmem/RAM[4][4] ,\dmem/RAM[4][3] ,\dmem/RAM[4][2] ,\dmem/RAM[4][1] ,\dmem/RAM[4][0] ,\dmem/a[31] ,\dmem/a[30] ,\dmem/a[29] ,\dmem/a[28] ,\dmem/a[27] ,\dmem/a[26] ,\dmem/a[25] ,\dmem/a[24] ,\dmem/a[23] ,\dmem/a[22] ,\dmem/a[21] ,\dmem/a[20] ,\dmem/a[19] ,\dmem/a[18] ,\dmem/a[17] ,\dmem/a[16] ,\dmem/a[15] ,\dmem/a[14] ,\dmem/a[13] ,\dmem/a[12] ,\dmem/a[11] ,\dmem/a[10] ,\dmem/a[9] ,\dmem/a[8] ,\dmem/a[7] ,\dmem/a[6] ,\dmem/a[5] ,\dmem/a[4] ,\dmem/a[3] ,\dmem/a[2] ,\dmem/a[1] ,\dmem/a[0] ,\dmem/wd[31] ,\dmem/wd[30] ,\dmem/wd[29] ,\dmem/wd[28] ,\dmem/wd[27] ,\dmem/wd[26] ,\dmem/wd[25] ,\dmem/wd[24] ,\dmem/wd[23] ,\dmem/wd[22] ,\dmem/wd[21] ,\dmem/wd[20] ,\dmem/wd[19] ,\dmem/wd[18] ,\dmem/wd[17] ,\dmem/wd[16] ,\dmem/wd[15] ,\dmem/wd[14] ,\dmem/wd[13] ,\dmem/wd[12] ,\dmem/wd[11] ,\dmem/wd[10] ,\dmem/wd[9] ,\dmem/wd[8] ,\dmem/wd[7] ,\dmem/wd[6] ,\dmem/wd[5] ,\dmem/wd[4] ,\dmem/wd[3] ,\dmem/wd[2] ,\dmem/wd[1] ,\dmem/wd[0] ,\riscv/alu_A[31] ,\riscv/alu_A[30] ,\riscv/alu_A[29] ,\riscv/alu_A[28] ,\riscv/alu_A[27] ,\riscv/alu_A[26] ,\riscv/alu_A[25] ,\riscv/alu_A[24] ,\riscv/alu_A[23] ,\riscv/alu_A[22] ,\riscv/alu_A[21] ,\riscv/alu_A[20] ,\riscv/alu_A[19] ,\riscv/alu_A[18] ,\riscv/alu_A[17] ,\riscv/alu_A[16] ,\riscv/alu_A[15] ,\riscv/alu_A[14] ,\riscv/alu_A[13] ,\riscv/alu_A[12] ,\riscv/alu_A[11] ,\riscv/alu_A[10] ,\riscv/alu_A[9] ,\riscv/alu_A[8] ,\riscv/alu_A[7] ,\riscv/alu_A[6] ,\riscv/alu_A[5] ,\riscv/alu_A[4] ,\riscv/alu_A[3] ,\riscv/alu_A[2] ,\riscv/alu_A[1] ,\riscv/alu_A[0] ,\riscv/alu_B[31] ,\riscv/alu_B[30] ,\riscv/alu_B[29] ,\riscv/alu_B[28] ,\riscv/alu_B[27] ,\riscv/alu_B[26] ,\riscv/alu_B[25] ,\riscv/alu_B[24] ,\riscv/alu_B[23] ,\riscv/alu_B[22] ,\riscv/alu_B[21] ,\riscv/alu_B[20] ,\riscv/alu_B[19] ,\riscv/alu_B[18] ,\riscv/alu_B[17] ,\riscv/alu_B[16] ,\riscv/alu_B[15] ,\riscv/alu_B[14] ,\riscv/alu_B[13] ,\riscv/alu_B[12] ,\riscv/alu_B[11] ,\riscv/alu_B[10] ,\riscv/alu_B[9] ,\riscv/alu_B[8] ,\riscv/alu_B[7] ,\riscv/alu_B[6] ,\riscv/alu_B[5] ,\riscv/alu_B[4] ,\riscv/alu_B[3] ,\riscv/alu_B[2] ,\riscv/alu_B[1] ,\riscv/alu_B[0] ,\riscv/alu_Result[31] ,\riscv/alu_Result[30] ,\riscv/alu_Result[29] ,\riscv/alu_Result[28] ,\riscv/alu_Result[27] ,\riscv/alu_Result[26] ,\riscv/alu_Result[25] ,\riscv/alu_Result[24] ,\riscv/alu_Result[23] ,\riscv/alu_Result[22] ,\riscv/alu_Result[21] ,\riscv/alu_Result[20] ,\riscv/alu_Result[19] ,\riscv/alu_Result[18] ,\riscv/alu_Result[17] ,\riscv/alu_Result[16] ,\riscv/alu_Result[15] ,\riscv/alu_Result[14] ,\riscv/alu_Result[13] ,\riscv/alu_Result[12] ,\riscv/alu_Result[11] ,\riscv/alu_Result[10] ,\riscv/alu_Result[9] ,\riscv/alu_Result[8] ,\riscv/alu_Result[7] ,\riscv/alu_Result[6] ,\riscv/alu_Result[5] ,\riscv/alu_Result[4] ,\riscv/alu_Result[3] ,\riscv/alu_Result[2] ,\riscv/alu_Result[1] ,\riscv/alu_Result[0] ,\riscv/ALUControl[2] ,\riscv/ALUControl[1] ,\riscv/ALUControl[0] ,\riscv/ALUSrc ,clk_p}),
    .clk_i(clk_p)
);

endmodule
