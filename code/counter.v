module counter (
    // peripheral clock signals
    input        clk,
    input        rst_n,
    // register facing signals
    output [15:0] count_val,
    input  [15:0] period,
    input         en,
    input         count_reset,
    input         upnotdown,
    input  [7:0]  prescale
);

    reg [15:0] r_count_val;
    reg [15:0] r_presc_cnt;

    assign count_val = r_count_val;

    // calculăm "targetul" prescalerului: 2^prescale
    wire [15:0] prescale_target;

    assign prescale_target = 16'h0001 << prescale;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_count_val <= 16'h0000;
            r_presc_cnt <= 16'h0000;
        end else begin
            // reset prioritar la toti registrii de numarare
            if (count_reset) begin
                r_count_val <= 16'h0000;
                r_presc_cnt <= 16'h0000;
            end else if (!en) begin
                // dacă e oprit, înghețăm numărătoarea, dar resetăm prescalerul
                r_presc_cnt <= 16'h0000;
                // count_val rămâne cum era
            end else begin
                // en == 1, count_reset == 0
                // prescaler
                if (prescale_target <= 16'h0001) begin
                    // cazul prescale = 0 -> tick la fiecare ciclu
                    r_presc_cnt <= 16'h0000;
                    // facem un tick la fiecare clock
                    if (upnotdown) begin
                        // up-count
                        if (r_count_val >= period)
                           r_count_val <= 16'h0000;
                        else
                            r_count_val <= r_count_val + 16'h0001;
                    end else begin
                        // down-count
                        if (r_count_val == 16'h0000)
                            r_count_val <= period;
                        else
                            r_count_val <= r_count_val - 16'h0001;
                    end
                end else begin
                    // prescaler > 0
                    if (r_presc_cnt >= (prescale_target - 16'h0001)) begin
                        r_presc_cnt <= 16'h0000;
                        // tick de counter
                        if (upnotdown) begin
                            if (r_count_val >= period)
                                r_count_val <= 16'h0000;
                            else
                                r_count_val <= r_count_val + 16'h0001;
                        end else begin
                            if (r_count_val == 16'h0000)
                                r_count_val <= period;
                            else
                                r_count_val <= r_count_val - 16'h0001;
                        end
                    end else begin
                        // încă numărăm în prescaler
                        r_presc_cnt <= r_presc_cnt + 16'h0001;
                    end
                end
            end
        end
    end

endmodule