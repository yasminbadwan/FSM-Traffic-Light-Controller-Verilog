`timescale 1ns/1ps

module traffic_ctrl(
    input  clk,
    input  rst,
    input  VS,
    input  PB,
    output reg [2:0] light_main,
    output reg [2:0] light_side,
    output reg walk
);

    reg [2:0] presnt_state, next_state;

    parameter [2:0]
        MG  = 3'd0,
        MY  = 3'd1,
        AR  = 3'd2,
        SG  = 3'd3,
        SY  = 3'd4,
        PG  = 3'd5;

    parameter [2:0]
        Red = 3'b100,
        yel = 3'b010,
        GRN = 3'b001;

    reg [31:0] timer;
    reg ped_pending;
    reg ar_return;

    // =============================
    // State register + timer
    // =============================
    always @(posedge clk or negedge rst) begin
        if (~rst) begin
            presnt_state <= MG;
            timer        <= 0;
            ped_pending  <= 1'b0;
            ar_return    <= 1'b0;
        end else begin
            presnt_state <= next_state;

            if (presnt_state != next_state)
                timer <= 0;
            else
                timer <= timer + 1;

            // Save pedestrian request during SG or SY
            if ((presnt_state == SG) || (presnt_state == SY)) begin
                if (PB)
                    ped_pending <= 1'b1;
            end

            // Clear pending when PG is served
            if (next_state == PG)
                ped_pending <= 1'b0;

            // Decide AR return direction
            if (presnt_state == MY && next_state == AR)
                ar_return <= 1'b0;          // decision AR
            else if ((presnt_state == SY && next_state == AR) ||
                     (presnt_state == PG && next_state == AR))
                ar_return <= 1'b1;          // return to MG
        end
    end

    // =============================
    // Next state logic
    // =============================
    always @(*) begin
        next_state = presnt_state;

        case (presnt_state)
            MG: if (timer >= 60 && (VS || PB || ped_pending))
                    next_state = MY;

            MY: next_state = AR;

            AR: begin
                if (ar_return)
                    next_state = MG;
                else if (PB || ped_pending)
                    next_state = PG;
                else if (VS)
                    next_state = SG;
            end

            SG: if (timer >= 40)
                    next_state = SY;

            SY: next_state = AR;

            PG: if (timer >= 40)
                    next_state = AR;
        endcase
    end

    // =============================
    // Output logic
    // =============================
    always @(*) begin
        light_main = Red;
        light_side = Red;
        walk       = 1'b0;

        case (presnt_state)
            MG: begin
                light_main = GRN;
                light_side = Red;
            end
            MY: begin
                light_main = yel;
                light_side = Red;
            end
            AR: begin
                light_main = Red;
                light_side = Red;
            end
            SG: begin
                light_main = Red;
                light_side = GRN;
            end
            SY: begin
                light_main = Red;
                light_side = yel;
            end
            PG: begin
                light_main = Red;
                light_side = Red;
                walk       = 1'b1;
            end
        endcase
    end

endmodule  



`timescale 1ns/1ps

// ======================================================
//  TEST GENERATOR
// ======================================================
module tb_gen (
  input  wire clk,
  output reg  rst,
  output reg  VS,
  output reg  PB
);

  task wait_clk(input integer n);
    integer i;
    begin
      for (i=0; i<n; i=i+1) @(posedge clk);
    end
  endtask

  task do_reset;
    begin
      VS = 0; PB = 0; rst = 1;
      wait_clk(1);
      rst = 0;       
      wait_clk(2);
      rst = 1;
      wait_clk(1);
    end
  endtask

  // =========================
  // Case 10
  //
  // =========================
  task case_VS_only;
    begin
      VS = 1; PB = 0;

      wait_clk(60);  // MG 
      wait_clk(1);   // MY
      wait_clk(1);   // AR 
      wait_clk(40);  // SG 
      wait_clk(1);   // SY
      wait_clk(1);   // AR 
      VS = 0;
      wait_clk(5);
    end
  endtask

  // =========================
  // Case 01
  // =========================
  task case_PB_only;
    begin
      VS = 0; PB = 1;

      wait_clk(60);  // MG 
      wait_clk(1);   // MY
      wait_clk(1);   // AR 
      wait_clk(40);  // PG 
      wait_clk(1);   // AR 
      PB = 0;
      wait_clk(5);
    end
  endtask

  // =========================
  // Case 11
  // =========================
  task case_VS_PB;
    begin
      VS = 1; PB = 1;

      wait_clk(60);	  // MG 
      wait_clk(1);	  // MY
      wait_clk(1);    // AR 
      wait_clk(40);	  // PG 
      wait_clk(1);	  // AR 

      VS = 0; PB = 0;
      wait_clk(5);
    end
  endtask

  // =========================
  // Pending
  // =========================
  task case_pending;
    begin
      VS = 1; PB = 0;

      wait_clk(60); // MG
      wait_clk(1);  // MY
      wait_clk(1);  // AR 
      PB = 1;
      wait_clk(100);  
      PB = 0;
      wait_clk(35);
      wait_clk(1);  // SY
      wait_clk(1);  // AR 
      VS = 0;
      wait_clk(60); // MG
      wait_clk(1);  // MY
      wait_clk(1);  // AR 
      wait_clk(40); // PG
      wait_clk(1);  // AR 

      wait_clk(5);
    end
  endtask

  initial begin
    rst = 1; VS = 0; PB = 0;

    // Case 00
    do_reset();
    VS=0; PB=0;
    wait_clk(120);

    // Case 10
    do_reset();
    case_VS_only();

    // Case 01
    do_reset();
    case_PB_only();

    // Case 11
    do_reset();
    case_VS_PB();

    // Pending
    do_reset();
    case_pending();

    $finish;
  end

endmodule


// ======================================================
//  EXPECTED 
// ======================================================
module tb_expected (
  input  wire [2:0] state,
  output reg  [2:0] expMain,
  output reg  [2:0] expSide,
  output reg        expWalk
);

   parameter [2:0] RED = 3'b100, YEL = 3'b010, GRN = 3'b001;
   parameter [2:0] MG  = 3'd0,  MY  = 3'd1,  AR  = 3'd2,
                   SG  = 3'd3,  SY  = 3'd4,  PG  = 3'd5;

  always @(*) begin
    expMain = RED;
    expSide = RED;
    expWalk = 1'b0;

    case (state)
      MG: begin expMain = GRN; expSide = RED; end
      MY: begin expMain = YEL; expSide = RED; end
      AR: begin expMain = RED; expSide = RED; end
      SG: begin expMain = RED; expSide = GRN; end
      SY: begin expMain = RED; expSide = YEL; end
      PG: begin expMain = RED; expSide = RED; expWalk = 1'b1; end
      default: begin expMain = RED; expSide = RED; expWalk = 1'b0; end
    endcase
  end

endmodule


// ======================================================
// ANALYZE
// ======================================================
module tb_analyze (
  input  wire       clk,
  input  wire       rst,
  input  wire [2:0] state,

  input  wire [2:0] light_main,
  input  wire [2:0] light_side,
  input  wire       walk,

  input  wire [2:0] expMain,
  input  wire [2:0] expSide,
  input  wire       expWalk,

  output reg  [31:0] errors,
  output reg         saw_SG,
  output reg         saw_PG
);

  parameter [2:0] SG = 3'd3, PG = 3'd5;

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      errors <= 0;
      saw_SG <= 0;
      saw_PG <= 0;
    end else begin
      if (light_main !== expMain || light_side !== expSide || walk !== expWalk)
        errors <= errors + 1;

      if (state == SG) saw_SG <= 1'b1;
      if (state == PG) saw_PG <= 1'b1;
    end
  end

endmodule

// ======================================================
// traffic_ctrl_top
// ======================================================
module tb_traffic_ctrl_top;

  reg clk;
  initial clk = 0;
  always #10 clk = ~clk;    


  wire rst, VS, PB;
  wire [2:0] light_main, light_side;
  wire walk;
  wire [2:0] state;
  wire [2:0] expMain, expSide;
  wire expWalk;
  wire [31:0] errors;
  wire saw_SG, saw_PG;

  traffic_ctrl dut (
    .clk(clk), .rst(rst),
    .VS(VS), .PB(PB),
    .light_main(light_main),
    .light_side(light_side),
    .walk(walk)
  );

  assign state = dut.presnt_state;

 tb_gen GEN (
  .clk(clk),
  .rst(rst),
  .VS(VS),
  .PB(PB)
);
  tb_expected EXP (
    .state(state),
    .expMain(expMain),
    .expSide(expSide),
    .expWalk(expWalk)
  );
  tb_analyze ANA (
    .clk(clk),
    .rst(rst),
    .state(state),
    .light_main(light_main),
    .light_side(light_side),
    .walk(walk),
    .expMain(expMain),
    .expSide(expSide),
    .expWalk(expWalk),
    .errors(errors),
    .saw_SG(saw_SG),
    .saw_PG(saw_PG)
  );

endmodule
