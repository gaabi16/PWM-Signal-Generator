module pwm_gen (
    // peripheral clock signals
    input clk,
    input rst_n,
    // PWM signal register configuration
    input pwm_en,
    input[15:0] period,
    input[7:0] functions,
    input[15:0] compare1,
    input[15:0] compare2,
    input[15:0] count_val,
    // top facing signals
    output reg pwm_out
);

    // extrag modurile de functionare din registru
    wire align_mode  = functions[1]; // 0 = aligned, 1 = unaligned
    wire align_right = functions[0]; // 0 = left, 1 = right (doar in aligned mode)

    wire unused_period = |period; // ca sa nu dea warning

    always @(*) begin
        // valoare default
        pwm_out = 1'b0;

        // reset asincron => iesirea low
        if (!rst_n) begin
            pwm_out = 1'b0;
        end 
        else if (!pwm_en) begin // pwm dezactivat => iesirea ramane low
            pwm_out = 1'b0;
        end 
        else if (compare1 == compare2) begin // daca compare1 == compare2 nu se genereaza nimic
            pwm_out = 1'b0;
        end 
        else begin
            if (!align_mode) begin // aligned mode
                if (!align_right) begin // left aligned => high pana la compare1
                    if (compare1 == 16'd0)
                        pwm_out = 1'b0;
                    else if (count_val <= compare1) semnal high atata timp cat counter <= compare1
                        pwm_out = 1'b1;
                    else
                        pwm_out = 1'b0;
                end else begin
                    if (count_val < compare1) // right aligned => high cand count_val >= compare1
                        pwm_out = 1'b0;
                    else
                        pwm_out = 1'b1;
                end
            end else begin
                // unaligned mode => high intre compare1 si compare2
                if (count_val < compare1)
                    pwm_out = 1'b0;
                else if (count_val < compare2)
                    pwm_out = 1'b1;
                else
                    pwm_out = 1'b0;
            end
        end
    end

endmodule
