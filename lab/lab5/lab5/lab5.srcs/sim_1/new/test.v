`timescale 1ns / 1ps

module test();

    reg clk,rst;
    //IO_BUS
    wire [7:0] io_addr;
    wire [31:0] io_dout;
    wire io_we;
    reg [31:0] io_din;
    //Debug_BUS
    reg [7:0] m_rf_addr;
    wire [31:0] rf_data;
    wire [31:0] m_data;
    //PC/IF/ID register
    wire [31:0] pc;
    wire [31:0] pcd; //pc_id
    wire [31:0] ir; //inst_id
    wire [31:0] pcin;
    //ID/EX register
    wire [31:0] pce;//pc_ex
    wire [31:0] a; //rf_rdata1_ex
    wire [31:0] b;   //rf_rdata2_ex 
    wire [31:0] imm; 
    wire [31:0] rd;
    wire [31:0] ctrl;
    wire [31:0] y;
    wire [31:0] bm;
    wire [31:0] rdm;
    wire [31:0] ctrlm;
    //MEM/WB register
    reg [31:0] yw;
    reg [31:0] mdr;
    wire [31:0] rdw;
    wire [31:0] ctrlw;

    initial begin
        rst = 1;clk = 0;
        #5 rst = 0;
        forever #5 clk = ~clk;
    end
    initial begin
        #410 $finish;
    end
    initial begin
        io_din = 0;
    #200 io_din = 1;
    end
    initial begin
            m_rf_addr=6;
        #70 m_rf_addr=7;
        #10 m_rf_addr=28;
        #10 m_rf_addr=29;
        #30 m_rf_addr=6;
        #90 m_rf_addr=1;
        #10 m_rf_addr=6;
    end
//cpu

//IF/ID registers
reg [31:0] IF_ID_pc;
reg [31:0] IF_ID_pc_plus4;
reg [31:0] IF_ID_instruction;

//ID/EX registers
reg [31:0] ID_EX_pc;
reg [31:0] ID_EX_pc_plus4;
reg [31:0] ID_EX_reg1;
reg [31:0] ID_EX_reg2;
reg [31:0] ID_EX_imm;
reg [4:0]  ID_EX_reg_w_addr;
reg [1:0]  ID_EX_reg_write_sel; // 0: alu result, 1: pc+4, 2: mem
reg [1:0]  ID_EX_alu_a_sel; // 0: reg1, 1: pc, 2: EX/MEM, 3: MEM/WB
reg [1:0]  ID_EX_alu_b_sel; // 0: reg2, 1: imm, 2: EX/MEM, 3: MEM/WB
reg [2:0]  ID_EX_alu_opcode; //0: add, 1: sub, 2: and, 3: or, 4: xor, 5: shift left, 6: shift right
reg        ID_EX_mem_write_sel; //0: data, 1: MEM/WB
reg        ID_EX_mem_write;
reg [1:0]  ID_EX_sw_r2_sel;
wire stall;
wire flush;


//EX/MEM registers
reg [31:0] EX_MEM_pc_plus4;
reg [31:0] EX_MEM_alu_result;
reg [31:0] EX_MEM_data_mem_data;
reg [4:0]  EX_MEM_reg_w_addr;
reg [1:0]  EX_MEM_reg_write_sel; // 0: alu result, 1: pc+4, 2: mem
reg        EX_MEM_mem_write_sel; //0: data, 1: MEM/WB
reg        EX_MEM_mem_write;

//MEM/WB registers
reg [31:0] MEM_WB_reg_w_data;
reg [4:0]  MEM_WB_reg_w_addr;


//IF stage

    //pc
    reg [31:0] pc_input;
    PC PC(
        .clk(clk),
        .rst(rst),
        .en(~stall),
        .pc_input(pc_input),
        .pc(pc)
    );

    //instruction memory
    wire [31:0] instruction;
    instruction_mem instruction_mem(
        .a(pc[9:2]),
        .spo(instruction)
    );

    always@(posedge clk or posedge rst)begin
        if(rst | flush)begin
            IF_ID_pc <= 0;
            IF_ID_pc_plus4 <= 0;
            IF_ID_instruction <= 0;
        end
        else if(~stall)begin
            IF_ID_pc <= pc;
            IF_ID_pc_plus4 <= pc + 4;
            IF_ID_instruction <= instruction;
        end
    end

//ID stage

    //register file
    wire [4:0] reg_addr1;
    wire [4:0] reg_addr2;
    wire [31:0] reg_data1;
    wire [31:0] reg_data2;
    register_file register_file(
        .clk(clk),
        .rst(rst),
        .read_register1(reg_addr1),
        .read_register2(reg_addr2),
        .write_register(MEM_WB_reg_w_addr),
        .write_data(MEM_WB_reg_w_data),
        .read_data1(reg_data1),
        .read_data2(reg_data2),
        .debug_register(m_rf_addr[4:0]),
        .debug_register_data(rf_data)
    );

    //imm
    wire [31:0] Imm;
    imme imme(.inst(IF_ID_instruction),.imme(Imm));

    //branch
    wire [1:0] branch_type;
    wire [31:0] branch_input1;
    wire [31:0] branch_input2;
    wire branch_signal;
    branch branch(
        .branch_type(branch_type),
        .input1(branch_input1),
        .input2(branch_input2),
        .branch_signal(branch_signal)
    );

    //decode
    wire [4:0] reg_write_addr;
    wire [1:0] reg_write_sel;
    wire mem_write;
    wire [1:0] alu_a_sel;
    wire [1:0] alu_b_sel;
    wire [2:0] alu_opcode;
    wire is_r1_ID_needed;
    wire is_r2_ID_needed;
    wire is_r1_EX_needed;
    wire is_r2_EX_needed;
    wire is_r2_MEM_needed;
    wire is_jal;
    wire is_jalr;
    wire is_branch;
    
    decode decode(
        .instruction(IF_ID_instruction),
        .reg_addr1(reg_addr1),
        .reg_addr2(reg_addr2),
        .reg_write_addr(reg_write_addr),
        .reg_write_sel(reg_write_sel),
        .mem_write(mem_write),
        .alu_a_sel(alu_a_sel),
        .alu_b_sel(alu_b_sel),
        .alu_opcode(alu_opcode),
        .is_r1_ID_needed(is_r1_ID_needed),
        .is_r2_ID_needed(is_r2_ID_needed),
        .is_r1_EX_needed(is_r1_EX_needed),
        .is_r2_EX_needed(is_r2_EX_needed),
        .is_r2_MEM_needed(is_r2_MEM_needed),
        .is_jal(is_jal),
        .is_jalr(is_jalr),
        .is_branch(is_branch),
        .branch_type(branch_type)
    );

    //hazerds detection 
    wire [1:0] id_ex_alu_a_sel;
    wire [1:0] id_ex_alu_b_sel;
    wire [1:0] id_ex_sw_r2_sel;
    wire id_ex_mem_write_sel;
    wire [31:0] jalr_reg;
    hazerd_detection hazerd_detection(
        .ID_EX_reg_w_addr(ID_EX_reg_w_addr),
        .EX_MEM_reg_w_addr(EX_MEM_reg_w_addr),
        .ID_EX_reg_write_sel(ID_EX_reg_write_sel),
        .EX_MEM_reg_write_sel(EX_MEM_reg_write_sel),
        .reg_addr1(reg_addr1),
        .reg_addr2(reg_addr2),
        .is_r1_ID_needed(is_r1_ID_needed),
        .is_r2_ID_needed(is_r2_ID_needed),
        .is_r1_EX_needed(is_r1_EX_needed),
        .is_r2_EX_needed(is_r2_EX_needed),
        .is_r2_MEM_needed(is_r2_MEM_needed),
        .alu_a_sel(alu_a_sel),
        .alu_b_sel(alu_b_sel),
        .is_branch(is_branch),
        .is_jump(is_jal | is_jalr),
        .branch_signal(branch_signal),
        .reg_data1(reg_data1),
        .reg_data2(reg_data2),
        .EX_MEM_alu_result(EX_MEM_alu_result),
        .ID_EX_alu_a_sel(id_ex_alu_a_sel),
        .ID_EX_alu_b_sel(id_ex_alu_b_sel),
        .ID_EX_sw_r2_sel(id_ex_sw_r2_sel),
        .branch_input1(branch_input1),
        .branch_input2(branch_input2),
        .jalr_reg(jalr_reg),
        .ID_EX_mem_write_sel(id_ex_mem_write_sel),
        .stall(stall),
        .flush(flush)
    );
   
    //pc 
    
    always@(*)begin
        if((is_branch & branch_signal) | is_jal)
            pc_input = IF_ID_pc + Imm;
        else if(is_jalr)
            pc_input = jalr_reg + Imm;
        else
            pc_input = pc + 4;
    end

    //ID->EX
    always@(posedge clk or posedge rst)begin
        if(rst | stall)begin
            ID_EX_pc <= 0;
            ID_EX_pc_plus4 <= 0;
            ID_EX_reg1 <= 0;
            ID_EX_reg2 <= 0;
            ID_EX_imm <= 0;
            ID_EX_reg_w_addr <= 0;
            ID_EX_reg_write_sel <= 0;
            ID_EX_alu_a_sel <= 0;
            ID_EX_alu_b_sel <= 0;
            ID_EX_alu_opcode <= 0;
            ID_EX_mem_write_sel <= 0;
            ID_EX_mem_write <= 0;
            ID_EX_sw_r2_sel <= 0;
        end
        else begin
            ID_EX_pc <= IF_ID_pc;
            ID_EX_pc_plus4 <= IF_ID_pc_plus4;
            ID_EX_reg1 <= reg_data1;
            ID_EX_reg2 <= reg_data2;
            ID_EX_imm <= Imm;
            ID_EX_reg_w_addr <= reg_write_addr;
            ID_EX_reg_write_sel <= reg_write_sel;
            ID_EX_alu_a_sel <= id_ex_alu_a_sel;
            ID_EX_alu_b_sel <= id_ex_alu_b_sel;
            ID_EX_alu_opcode <= alu_opcode;
            ID_EX_mem_write_sel <= id_ex_mem_write_sel;
            ID_EX_mem_write <= mem_write;
            ID_EX_sw_r2_sel <= id_ex_sw_r2_sel;
        end
    end

//EX stage

    //alu
    reg [31:0] operant1;
    reg [31:0] operant2;
    wire [31:0] alu_result;
    alu alu(
        .operant1(operant1),
        .operant2(operant2),
        .operation_code(ID_EX_alu_opcode),
        .result(alu_result)
    );

    always@(*)begin
        case(ID_EX_alu_a_sel)
        2'h0:operant1 = ID_EX_reg1;
        2'h1:operant1 = ID_EX_pc;
        2'h2:operant1 = EX_MEM_alu_result;
        2'h3:operant1 = MEM_WB_reg_w_data;
        endcase
    end

    always@(*)begin
        case(ID_EX_alu_b_sel)
        2'h0:operant2 = ID_EX_reg2;
        2'h1:operant2 = ID_EX_imm;
        2'h2:operant2 = EX_MEM_alu_result;
        2'h3:operant2 = MEM_WB_reg_w_data;
        endcase
    end

    //EX->MEM
    always@(posedge clk or posedge rst)begin
        if(rst)begin
            EX_MEM_pc_plus4 <= 0;
            EX_MEM_alu_result <= 0;
            EX_MEM_data_mem_data <= 0;
            EX_MEM_reg_w_addr <= 0;
            EX_MEM_reg_write_sel <= 0;
            EX_MEM_mem_write_sel <= 0;
            EX_MEM_mem_write <= 0;
        end
        else begin
            EX_MEM_pc_plus4 <= ID_EX_pc_plus4;
            EX_MEM_alu_result <= alu_result;
            case(ID_EX_sw_r2_sel)
            2'h0:EX_MEM_data_mem_data <= ID_EX_reg2;
            2'h1:EX_MEM_data_mem_data <= EX_MEM_alu_result;
            2'h2:EX_MEM_data_mem_data <= MEM_WB_reg_w_data;
            default:;
            endcase
            EX_MEM_reg_w_addr <= ID_EX_reg_w_addr;
            EX_MEM_reg_write_sel <= ID_EX_reg_write_sel;
            EX_MEM_mem_write_sel <= ID_EX_mem_write_sel;
            EX_MEM_mem_write <= ID_EX_mem_write;
        end
    end

//MEM stage

    //data memory
    wire [31:0] write_data = EX_MEM_mem_write_sel ? MEM_WB_reg_w_data : EX_MEM_data_mem_data;
    wire [31:0] read_data;
    data_io_memory data_io_memory(
        .clk(clk),
        .write_enable(EX_MEM_mem_write),
        .addr(EX_MEM_alu_result),
        .write_data(write_data),
        .read_data(read_data),
        .io_we(io_we),
        .io_addr(io_addr),
        .io_dout(io_dout),
        .io_din(io_din),
        .m_rf_addr(m_rf_addr),
        .m_data(m_data)
    );

    always@(posedge clk or posedge rst)begin
        if(rst)begin
            MEM_WB_reg_w_data <= 0;
            MEM_WB_reg_w_addr <= 0;
        end
        else begin
            case(EX_MEM_reg_write_sel)
            2'h0:MEM_WB_reg_w_data <= EX_MEM_alu_result;
            2'h1:MEM_WB_reg_w_data <= EX_MEM_pc_plus4;
            2'h2:MEM_WB_reg_w_data <= read_data;
            default:MEM_WB_reg_w_data <= 0;
            endcase
            MEM_WB_reg_w_addr <= EX_MEM_reg_w_addr;
        end
    end

//output modules
    assign pcd = IF_ID_pc;
    assign ir = IF_ID_instruction;
    assign pcin = pc_input;
    assign pce = ID_EX_pc;
    assign a = ID_EX_reg1;
    assign b = ID_EX_reg2;
    assign imm = ID_EX_imm;
    assign rd = ID_EX_reg_w_addr;
    assign ctrl = {stall,stall,(~stall & flush),flush,2'b0,ID_EX_alu_a_sel,2'b0,ID_EX_alu_b_sel,1'b0,(ID_EX_reg_w_addr != 5'h0),ID_EX_reg_write_sel,2'b0,(ID_EX_reg_write_sel == 2'h2),ID_EX_mem_write,2'b0,(is_jal | is_jalr),(is_branch & branch_signal),2'b0,alu_a_sel[0],alu_b_sel[0],ID_EX_alu_opcode}; 
    assign y = EX_MEM_alu_result;
    assign bm = EX_MEM_mem_write_sel ? MEM_WB_reg_w_data : EX_MEM_data_mem_data;
    assign rdm = EX_MEM_reg_w_addr;
    assign ctrlm = {26'b0,EX_MEM_reg_write_sel,2'b0,EX_MEM_mem_write,EX_MEM_mem_write_sel};
    always@(posedge clk or posedge rst)begin
        if(rst)begin
            yw <= 0;
            mdr <= 0;
        end
        else begin
            yw <= (EX_MEM_reg_write_sel == 2'h0) ? EX_MEM_alu_result : EX_MEM_pc_plus4;
            mdr <= read_data;
        end
    end
    assign rdw = MEM_WB_reg_w_addr;
    assign ctrlw = {31'b0,(MEM_WB_reg_w_addr != 5'h0)};
   

endmodule
