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
    // extragere de biti de configurare din registrul functions
    wire align_left_right = functions[0];  // 0 = stanga, 1 = dreapta
    wire aligned_mode = functions[1];      // 0 = aliniat, 1 = nealiniat
    
    // registru pentru detectarea tranzitiei overflow
    reg [15:0] last_count_val;
    
    
    wire overflow_event = (count_val == period); // detectare cand counterul a ajuns la PERIOD
    // Overflow = count_val trece de la period la 0
    wire wrap_event = (count_val == 0 && last_count_val == period); 
    wire overflow_underflow = overflow_event || wrap_event; // detectare inceputul unei noi perioade
    
    // flag pentru detectarea frontului
    reg last_overflow_underflow;
    
    // registrii pentru retinerea configuratiei la overflow/underflow
    reg[15:0] active_period;
    reg[15:0] active_compare1;
    reg[15:0] active_compare2;
    reg active_align_left_right;
    reg active_aligned_mode;
    
    // sincronizare la ceas sau la reset asincron
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // initializare la reset
            pwm_out <= 1'b0;
            last_overflow_underflow <= 1'b0;
            last_count_val <= 16'h0000;
            active_period <= 16'h0000;
            active_compare1 <= 16'h0000;
            active_compare2 <= 16'h0000;
            active_align_left_right <= 1'b0;
            active_aligned_mode <= 1'b0;
        end else begin
            // memorare valoarea anterioara a counterului
            last_count_val <= count_val;
            
            // memorare stare overflow pentru detectarea frontului
            last_overflow_underflow <= overflow_underflow;
            
            // actualizarea registrilor la overflow
            if (overflow_underflow && !last_overflow_underflow) begin
                active_period <= period;
                active_compare1 <= compare1;
                active_compare2 <= compare2;
                active_align_left_right <= align_left_right;
                active_aligned_mode <= aligned_mode;
            end
            
            // generarea semnalului PWM
            if (!pwm_en) begin // daca pwm_en e dezactivat => se mentine ultima stare
                pwm_out <= pwm_out;
            end else begin
                // verificarea modului aliniat / nealiniat
                if (!active_aligned_mode) begin // aliniat 
                    // verificare left aligned / right aligned
                    if (!active_align_left_right) begin
                        // left aligned:
                        // daca perioada a inceput (se detecteaza frontul pozitiv al overflowului)
                        // atunci pwm incepe HIGH, pe 1
                        if (overflow_underflow && !last_overflow_underflow) begin
                            pwm_out <= 1'b1;
                        // cand counterul ajunge la compare1 => pwm devine 0
                        end else if (count_val == active_compare1) begin
                            pwm_out <= 1'b0;
                        end
                    end else begin
                        // right aligned: (analog cu left aligned)
                        // pwm incepe pe 0 la overflow, schimba in 1 la compare1
                        if (overflow_underflow && !last_overflow_underflow) begin
                            pwm_out <= 1'b0;
                        end else if (count_val == active_compare1) begin
                            pwm_out <= 1'b1;
                        end
                    end
                end else begin // nealiniat
                    // pwm incepe pe 0, devine 1 la compare1, revine la 0 la compare2
                    if (overflow_underflow && !last_overflow_underflow) begin
                        pwm_out <= 1'b0;
                    end else if (count_val == active_compare1) begin
                        pwm_out <= 1'b1;
                    end else if (count_val == active_compare2) begin
                        pwm_out <= 1'b0;
                    end
                end
            end
        end
    end
endmodule