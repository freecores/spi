//////////////////////////////////////////////////////////////////////
////                                                              ////
////  tb_spi_top.v                                                ////
////                                                              ////
////  This file is part of the SPI IP core project                ////
////  http://www.opencores.org/projects/spi/                      ////
////                                                              ////
////  Author(s):                                                  ////
////      - Simon Srot (simons@opencores.org)                     ////
////                                                              ////
////  Based on:                                                   ////
////      - i2c/bench/verilog/tst_bench_top.v                     ////
////        Copyright (C) 2001 Richard Herveille                  ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2002 Authors                                   ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "timescale.v"

module tb_spi_top();

  reg         clk;
  reg         rst;
  wire [31:0] adr;
  wire [31:0] dat_i, dat_o;
  wire        we;
  wire  [3:0] sel;
  wire        stb;
  wire        cyc;
  wire        ack;
  wire        err;
  wire        int;

  wire  [7:0] ss;
  wire        sclk;
  wire        mosi;
  wire        miso;

  reg  [31:0] q;

  parameter SPI_RX     = 4'h0;
  parameter SPI_TX     = 4'h0;
  parameter SPI_CTRL   = 4'h4;
  parameter SPI_DEVIDE = 4'h8;
  parameter SPI_SS     = 4'hc;

  // Generate clock
  always #5 clk = ~clk;

  // Wishbone master model
  wb_master_model #(32, 32) i_wb_master (
    .clk(clk), .rst(rst),
    .adr(adr), .din(dat_i), .dout(dat_o),
    .cyc(cyc), .stb(stb), .we(we), .sel(sel), .ack(ack), .err(err), .rty(1'b0)
  );

  // SPI master core
  spi_top i_spi_top (
    .wb_clk_i(clk), .wb_rst_i(rst), 
    .wb_adr_i(adr[4:0]), .wb_dat_i(dat_o), .wb_dat_o(dat_i), 
    .wb_sel_i(sel), .wb_we_i(we), .wb_stb_i(stb), 
    .wb_cyc_i(cyc), .wb_ack_o(ack), .wb_err_o(err), .wb_int_o(int),
    .ss_pad_o(ss), .sclk_pad_o(sclk), .mosi_pad_o(mosi), .miso_pad_i(miso) 
  );

  // SPI slave model
  spi_slave_model i_spi_slave (
    .rst(rst), .ss(ss[0]), .sclk(sclk), .mosi(mosi), .miso(miso)
  );

  initial
    begin
      $display("\nstatus: %t Testbench started\n\n", $time);

      $dumpfile("bench.vcd");
      $dumpvars(1, tb_spi_top);
      $dumpvars(1, tb_spi_top.i_spi_slave);

      // Initial values
      clk = 0;

      i_spi_slave.rx_negedge = 1'b0;
      i_spi_slave.tx_negedge = 1'b0;

      // Reset system
      rst = 1'b0; // negate reset
      #2;
      rst = 1'b1; // assert reset
      repeat(20) @(posedge clk);
      rst = 1'b0; // negate reset

      $display("status: %t done reset", $time);
      
      @(posedge clk);

      // Program core
      i_wb_master.wb_write(0, SPI_DEVIDE, 32'h05); // set devider register
      i_wb_master.wb_write(0, SPI_TX, 32'h5a);     // set tx register to 0x5a
      i_wb_master.wb_write(0, SPI_CTRL, 32'h40);   // set 8 bit transfer
      i_wb_master.wb_write(0, SPI_SS, 32'h01);     // set ss 0

      $display("status: %t programmed registers", $time);

      i_wb_master.wb_cmp(0, SPI_DEVIDE, 32'h05);   // verify devider register
      i_wb_master.wb_cmp(0, SPI_TX, 32'h5a);       // verify tx register
      i_wb_master.wb_cmp(0, SPI_CTRL, 32'h40);     // verify tx register
      i_wb_master.wb_cmp(0, SPI_SS, 32'h01);       // verify ss register

      $display("status: %t verified registers", $time);

      i_spi_slave.rx_negedge = 1'b1;
      i_wb_master.wb_write(0, SPI_CTRL, 32'h41);   // set 8 bit transfer, start transfer

      $display("status: %t generate transfer:  8 bit (0x0000005a), msb first, tx posedge, rx negedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);

      if (i_spi_slave.data == 32'h5a)
        $display("status: %t transfer completed: 0x0000005a == 0x%x                          ok", $time, i_spi_slave.data);
      else
        $display("status: %t transfer completed: 0x0000005a != 0x%x                          nok", $time, i_spi_slave.data);

      i_spi_slave.rx_negedge = 1'b0;
      i_wb_master.wb_write(0, SPI_TX, 32'ha5);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h44);   // set 8 bit transfer, tx negedge
      i_wb_master.wb_write(0, SPI_CTRL, 32'h45);   // set 8 bit transfer, tx negedge, start transfer

      $display("status: %t generate transfer:  8 bit (0x0000005a), msb first, tx negedge, rx posedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);

      if (i_spi_slave.data == 32'h5aa5)
        $display("status: %t transfer completed: 0x00005aa5 == 0x%x                          ok", $time, i_spi_slave.data);
      else
        $display("status: %t transfer completed: 0x00005aa5 != 0x%x                          nok", $time, i_spi_slave.data);

      i_spi_slave.rx_negedge = 1'b0;
      i_wb_master.wb_write(0, SPI_TX, 32'h5aa5);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h184);   // set 16 bit transfer, tx negedge, lsb
      i_wb_master.wb_write(0, SPI_CTRL, 32'h185);   // set 16 bit transfer, tx negedge, start transfer

      $display("status: %t generate transfer: 16 bit (0x00005aa5), lsb first, tx negedge, rx posedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);


      if (i_spi_slave.data == 32'h5aa5a55a)
        $display("status: %t transfer completed: 0x5aa5a55a == 0x%x                          ok", $time, i_spi_slave.data);
      else
        $display("status: %t transfer completed: 0x5aa5a55a != 0x%x                          nok", $time, i_spi_slave.data);

      i_spi_slave.rx_negedge = 1'b0;
      i_spi_slave.tx_negedge = 1'b1;
      i_wb_master.wb_write(0, SPI_TX, 32'h55);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h144);   // set 8 bit transfer, tx negedge, lsb
      i_wb_master.wb_write(0, SPI_CTRL, 32'h145);   // set 8 bit transfer, tx negedge, start transfer

      $display("status: %t generate transfer:  8 bit (0x000000a5), lsb first, tx negedge, rx posedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);

      i_wb_master.wb_read(1, SPI_RX, q);

      if (i_spi_slave.data == 32'ha5a55aaa && q == 32'h00000055)
        $display("status: %t transfer completed: 0xa5a55aaa == 0x%x 0x0000005a == 0x%x ok", $time, i_spi_slave.data, q);
      else if (i_spi_slave.data == 32'ha5a55aaa)
        $display("status: %t transfer completed: 0xa5a55aaa == 0x%x 0x0000005a != 0x%x nok", $time, i_spi_slave.data, q);
      else if (q == 32'h0000005a)
        $display("status: %t transfer completed: 0xa5a55aaa != 0x%x 0x0000005a == 0x%x nok", $time, i_spi_slave.data, q);
      else
        $display("status: %t transfer completed: 0xa5a55aaa != 0x%x 0x0000005a != 0x%x nok", $time, i_spi_slave.data, q);

      i_spi_slave.rx_negedge = 1'b1;
      i_spi_slave.tx_negedge = 1'b0;
      i_wb_master.wb_write(0, SPI_TX, 32'haa);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h142);   // set 8 bit transfer, rx negedge, lsb
      i_wb_master.wb_write(0, SPI_CTRL, 32'h143);   // set 8 bit transfer, rx negedge, start transfer

      $display("status: %t generate transfer:  8 bit (0x000000aa), lsb first, tx posedge, rx negedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);

      i_wb_master.wb_read(1, SPI_RX, q);

      if (i_spi_slave.data == 32'ha55aaa55 && q == 32'h000000a5)
        $display("status: %t transfer completed: 0xa55aaa55 == 0x%x 0x000000a5 == 0x%x ok", $time, i_spi_slave.data, q);
      else if (i_spi_slave.data == 32'ha55aaa55)
        $display("status: %t transfer completed: 0xa55aaa55 == 0x%x 0x000000a5 != 0x%x nok", $time, i_spi_slave.data, q);
      else if (q == 32'h000000a5)
        $display("status: %t transfer completed: 0xa55aaa55 != 0x%x 0x000000a5 == 0x%x nok", $time, i_spi_slave.data, q);
      else
        $display("status: %t transfer completed: 0xa55aaa55 != 0x%x 0x000000a5 != 0x%x nok", $time, i_spi_slave.data, q);

      i_spi_slave.rx_negedge = 1'b1;
      i_spi_slave.tx_negedge = 1'b0;
      i_wb_master.wb_write(0, SPI_TX, 32'haa55);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h82);   // set 16 bit transfer, rx negedge
      i_wb_master.wb_write(0, SPI_CTRL, 32'h83);   // set 16 bit transfer, rx negedge, start transfer

      $display("status: %t generate transfer:  8 bit (0x0000aa55), msb first, tx posedge, rx negedge", $time);

      // Check bsy bit
      i_wb_master.wb_read(0, SPI_CTRL, q);
      while (q[0])
        i_wb_master.wb_read(1, SPI_CTRL, q);

      i_wb_master.wb_read(1, SPI_RX, q);

      if (i_spi_slave.data == 32'haa55aa55 && q == 32'h0000a55a)
        $display("status: %t transfer completed: 0xaa55aa55 == 0x%x 0x0000a55a == 0x%x ok", $time, i_spi_slave.data, q);
      else if (i_spi_slave.data == 32'haa55aa55)
        $display("status: %t transfer completed: 0xaa55aa55 == 0x%x 0x0000a55a != 0x%x nok", $time, i_spi_slave.data, q);
      else if (q == 32'h0000a55a)
        $display("status: %t transfer completed: 0xaa55aa55 != 0x%x 0x0000a55a == 0x%x nok", $time, i_spi_slave.data, q);
      else
        $display("status: %t transfer completed: 0xaa55aa55 != 0x%x 0x0000a55a != 0x%x nok", $time, i_spi_slave.data, q);

      i_spi_slave.rx_negedge = 1'b1;
      i_spi_slave.tx_negedge = 1'b1;
      i_wb_master.wb_write(0, SPI_TX, 32'haa55a5a5);
      i_wb_master.wb_write(0, SPI_CTRL, 32'h200);   // set 32 bit transfer, ie
      i_wb_master.wb_write(0, SPI_CTRL, 32'h201);   // set 32 bit transfer, start transfer

      $display("status: %t generate transfer: 32 bit (0xaa55a5a5), msb first, tx negedge, rx negedge", $time);

      // Check interrupt signal
      while (!int)
        @(posedge clk);

      i_wb_master.wb_read(1, SPI_RX, q);
    
      @(posedge clk);
      if (int)
        $display("status: %t transfer completed: interrupt still active                            nok", $time, i_spi_slave.data, q);

      if (i_spi_slave.data == 32'haa55a5a5 && q == 32'h552ad52a)
        $display("status: %t transfer completed: 0xaa55a5a5 == 0x%x 0x552ad52a == 0x%x ok", $time, i_spi_slave.data, q);
      else if (i_spi_slave.data == 32'haa55a5a5)
        $display("status: %t transfer completed: 0xaa55a5a5 == 0x%x 0x552ad52a != 0x%x nok", $time, i_spi_slave.data, q);
      else if (q == 32'h552ad52a)
        $display("status: %t transfer completed: 0xaa55a5a5 != 0x%x 0x552ad52a == 0x%x nok", $time, i_spi_slave.data, q);
      else
        $display("status: %t transfer completed: 0xaa55a5a5 != 0x%x 0x552ad52a != 0x%x nok", $time, i_spi_slave.data, q);

      i_spi_slave.rx_negedge = 1'b0;
      i_spi_slave.tx_negedge = 1'b0;
      i_wb_master.wb_write(0, SPI_CTRL, 32'h306);   // set 32 bit transfer, ie, lsb, rx negedge, tx negedge
      i_wb_master.wb_write(0, SPI_CTRL, 32'h307);   // set 32 bit transfer, start transfer

      $display("status: %t generate transfer: 32 bit (0xaa55a5a5), msb first, tx negedge, rx negedge", $time);

      // Check interrupt signal
      while (!int)
        @(posedge clk);

      i_wb_master.wb_read(1, SPI_RX, q);

      @(posedge clk);
      if (int)
        $display("status: %t transfer completed: interrupt still active                            nok", $time, i_spi_slave.data, q);

      if (i_spi_slave.data == 32'h54ab54aa && q == 32'ha5a5aa55)
        $display("status: %t transfer completed: 0x54ab54aa == 0x%x 0xa5a5aa55 == 0x%x ok", $time, i_spi_slave.data, q);
      else if (i_spi_slave.data == 32'h54ab54aa)
        $display("status: %t transfer completed: 0x54ab54aa == 0x%x 0xa5a5aa55 != 0x%x nok", $time, i_spi_slave.data, q);
      else if (q == 32'ha5a5aa55)
        $display("status: %t transfer completed: 0x54ab54aa != 0x%x 0xa5a5aa55 == 0x%x nok", $time, i_spi_slave.data, q);
      else
        $display("status: %t transfer completed: 0x54ab54aa != 0x%x 0xa5a5aa55 != 0x%x nok", $time, i_spi_slave.data, q);

      $display("\n\nstatus: %t Testbench done", $time);

      #25000; // wait 25us

      $stop;
    end

endmodule


