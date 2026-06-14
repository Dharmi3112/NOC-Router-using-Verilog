// FIFO MODULE
module fifo
#(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 4,
    parameter ADDR_WIDTH = 2
)
(
    input  clk,
    input  rst_n,
    input  wr_en,
    input  rd_en,
    input  [DATA_WIDTH-1:0]    data_in,
    output reg  [DATA_WIDTH-1:0]    data_out,
    output  empty,
    output  full
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;
    
    assign empty = (count == 0);
    assign full  = (count == DEPTH);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= 0;
            rd_ptr   <= 0;
            count    <= 0;
            data_out <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= data_in;
                    wr_ptr <= wr_ptr + 1;
                    count  <= count + 1;
                end
                2'b01: begin
                    data_out <= mem[rd_ptr];
                    rd_ptr   <= rd_ptr + 1;
                    count    <= count - 1;
                end
                2'b11: begin
                    mem[wr_ptr] <= data_in;
                    data_out    <= mem[rd_ptr];
                    wr_ptr      <= wr_ptr + 1;
                    rd_ptr      <= rd_ptr + 1;
                end
                default: begin
                end
            endcase
        end
    end

endmodule


// XY ROUTING LOGIC MODULE
module xy_routing
#(
    parameter CURR_X = 0,
    parameter CURR_Y = 0
)
(
    input  [1:0] dest_x,
    input  [1:0] dest_y,
    output reg [2:0] direction
);

    localparam LOCAL = 3'b000;
    localparam NORTH = 3'b001;
    localparam SOUTH = 3'b010;
    localparam EAST  = 3'b011;
    localparam WEST  = 3'b100;

    always @(*) begin
        if (dest_x > CURR_X)
            direction = EAST;
        else if (dest_x < CURR_X)
            direction = WEST;
        else if (dest_y > CURR_Y)
            direction = NORTH;
        else if (dest_y < CURR_Y)
            direction = SOUTH;
        else
            direction = LOCAL;
    end

endmodule


// ROUND-ROBIN ARBITER MODULE
module arbiter
#(
    parameter NUM_PORTS = 5
)
(
    input                   clk,
    input                   rst_n,
    input  [NUM_PORTS-1:0]  request,
    output reg  [NUM_PORTS-1:0]  grant
);

    reg [2:0] priority_ptr;
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_ptr <= 0;
            grant <= 0;
        end else begin
            grant = 0;
            
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                if (request[(priority_ptr + i) % NUM_PORTS] && grant == 0) begin
                    grant[(priority_ptr + i) % NUM_PORTS] = 1'b1;
                end
            end
            
            if (|grant) begin
                for (i = 0; i < NUM_PORTS; i = i + 1) begin
                    if (grant[i]) begin
                        priority_ptr <= (i + 1) % NUM_PORTS;
                    end
                end
            end
        end
    end

endmodule


// CROSSBAR SWITCH MODULE
module crossbar
#(
    parameter FLIT_WIDTH = 32,
    parameter NUM_PORTS = 5
)
(
    input  [NUM_PORTS-1:0]                 select,
    input  [NUM_PORTS*FLIT_WIDTH-1:0]      data_in,
    output reg  [FLIT_WIDTH-1:0]           data_out
);

    integer i;
    
    always @(*) begin
        data_out = 0;
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            if (select[i]) begin
                data_out = data_in[i*FLIT_WIDTH +: FLIT_WIDTH];
            end
        end
    end

endmodule


// INPUT PORT MODULE
module input_port
#(
    parameter FLIT_WIDTH = 32,
    parameter FIFO_DEPTH = 4,
    parameter CURR_X = 0,
    parameter CURR_Y = 0
)
(
    input                 clk,
    input  wire                  rst_n,
    input  wire [FLIT_WIDTH-1:0] flit_in,
    input  wire                  flit_in_valid,
    output wire                  flit_in_ready,
    output reg  [FLIT_WIDTH-1:0] flit_out,
    output reg                   flit_out_valid,
    input  wire                  flit_out_ready,
    output wire [2:0]            route_req,
    output wire                  is_header
);

    wire [FLIT_WIDTH-1:0] fifo_dout;
    wire fifo_empty, fifo_full;
    reg  fifo_rd_en;
    wire fifo_has_data;
    
    fifo #(
        .DATA_WIDTH(FLIT_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) input_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(flit_in_valid && flit_in_ready),
        .rd_en(fifo_rd_en),
        .data_in(flit_in),
        .data_out(fifo_dout),
        .empty(fifo_empty),
        .full(fifo_full)
    );
    
    assign flit_in_ready = !fifo_full;
    assign fifo_has_data = !fifo_empty;
    
    assign is_header = fifo_dout[31];
    wire [1:0] dest_x = fifo_dout[30:29];
    wire [1:0] dest_y = fifo_dout[28:27];
    
    xy_routing #(
        .CURR_X(CURR_X),
        .CURR_Y(CURR_Y)
    ) router (
        .dest_x(dest_x),
        .dest_y(dest_y),
        .direction(route_req)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_out <= 0;
            flit_out_valid <= 0;
        end else begin
            if (fifo_has_data && flit_out_ready) begin
                flit_out <= fifo_dout;
                flit_out_valid <= 1'b1;
            end else if (!fifo_has_data) begin
                flit_out_valid <= 1'b0;
            end
        end
    end
    
    always @(*) begin
        fifo_rd_en = fifo_has_data && flit_out_ready;
    end

endmodule


// SWITCH ALLOCATOR MODULE
module switch_allocator
#(
    parameter NUM_PORTS = 5
)
(
    input  clk,
    input  rst_n,
    input  wire [NUM_PORTS-1:0]      request_local,
    input  wire [NUM_PORTS-1:0]      request_north,
    input  wire [NUM_PORTS-1:0]      request_south,
    input  wire [NUM_PORTS-1:0]      request_east,
    input  wire [NUM_PORTS-1:0]      request_west,
    output wire [NUM_PORTS-1:0]      grant_local,
    output wire [NUM_PORTS-1:0]      grant_north,
    output wire [NUM_PORTS-1:0]      grant_south,
    output wire [NUM_PORTS-1:0]      grant_east,
    output wire [NUM_PORTS-1:0]      grant_west
);

    arbiter #(.NUM_PORTS(NUM_PORTS)) arb_local (
        .clk(clk), .rst_n(rst_n),
        .request(request_local),
        .grant(grant_local)
    );
    
    arbiter #(.NUM_PORTS(NUM_PORTS)) arb_north (
        .clk(clk), .rst_n(rst_n),
        .request(request_north),
        .grant(grant_north)
    );
    
    arbiter #(.NUM_PORTS(NUM_PORTS)) arb_south (
        .clk(clk), .rst_n(rst_n),
        .request(request_south),
        .grant(grant_south)
    );
    
    arbiter #(.NUM_PORTS(NUM_PORTS)) arb_east (
        .clk(clk), .rst_n(rst_n),
        .request(request_east),
        .grant(grant_east)
    );
    
    arbiter #(.NUM_PORTS(NUM_PORTS)) arb_west (
        .clk(clk), .rst_n(rst_n),
        .request(request_west),
        .grant(grant_west)
    );

endmodule


// OUTPUT PORT MODULE
module output_port
#(
    parameter FLIT_WIDTH = 32,
    parameter NUM_PORTS = 5
)
(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire [NUM_PORTS*FLIT_WIDTH-1:0]  flit_in_all,
    input  wire [NUM_PORTS-1:0]             grant,
    output wire [FLIT_WIDTH-1:0]            flit_out,
    output wire                             flit_out_valid,
    input  wire                             flit_out_ready
);
    wire [FLIT_WIDTH-1:0] selected_flit;
    
    crossbar #(
        .FLIT_WIDTH(FLIT_WIDTH),
        .NUM_PORTS(NUM_PORTS)
    ) xbar (
        .select(grant),
        .data_in(flit_in_all),
        .data_out(selected_flit)
    );
    
    assign flit_out = selected_flit;
    assign flit_out_valid = |grant;

endmodule


// ROUTER TOP MODULE
module NOC
#(
    parameter FLIT_WIDTH = 32,
    parameter NUM_PORTS = 5,
    parameter FIFO_DEPTH = 4,
    parameter CURR_X = 1,
    parameter CURR_Y = 1
)
(
    input  clk,
    input  rst_n,
    input  wire [FLIT_WIDTH-1:0] local_in_flit,
    input  wire                  local_in_valid,
    output wire                  local_in_ready,
    output wire [FLIT_WIDTH-1:0] local_out_flit,
    output wire                  local_out_valid,
    input  wire                  local_out_ready,
    input  wire [FLIT_WIDTH-1:0] north_in_flit,
    input  wire                  north_in_valid,
    output wire                  north_in_ready,
    output wire [FLIT_WIDTH-1:0] north_out_flit,
    output wire                  north_out_valid,
    input  wire                  north_out_ready,
    input  wire [FLIT_WIDTH-1:0] south_in_flit,
    input  wire                  south_in_valid,
    output wire                  south_in_ready,
    output wire [FLIT_WIDTH-1:0] south_out_flit,
    output wire                  south_out_valid,
    input  wire                  south_out_ready,
    input  wire [FLIT_WIDTH-1:0] east_in_flit,
    input  wire                  east_in_valid,
    output wire                  east_in_ready,
    output wire [FLIT_WIDTH-1:0] east_out_flit,
    output wire                  east_out_valid,
    input  wire                  east_out_ready,
    input  wire [FLIT_WIDTH-1:0] west_in_flit,
    input  wire                  west_in_valid,
    output wire                  west_in_ready,
    output wire [FLIT_WIDTH-1:0] west_out_flit,
    output wire                  west_out_valid,
    input  wire                  west_out_ready
);

    wire [FLIT_WIDTH-1:0] ip_flit_out [0:NUM_PORTS-1];
    wire                  ip_valid_out [0:NUM_PORTS-1];
    wire                  ip_ready_out [0:NUM_PORTS-1];
    wire [2:0]ip_route [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0] req_to_local, req_to_north, req_to_south, req_to_east, req_to_west;
    wire [NUM_PORTS-1:0] grant_from_local, grant_from_north, grant_from_south, grant_from_east, grant_from_west;
    wire [NUM_PORTS*FLIT_WIDTH-1:0] all_flits;
    
    genvar i;
    
    input_port #(.FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH), .CURR_X(CURR_X), .CURR_Y(CURR_Y)) 
    ip_local (
        .clk(clk), .rst_n(rst_n),
        .flit_in(local_in_flit), .flit_in_valid(local_in_valid), .flit_in_ready(local_in_ready),
        .flit_out(ip_flit_out[0]), .flit_out_valid(ip_valid_out[0]), .flit_out_ready(ip_ready_out[0]),
        .route_req(ip_route[0]), .is_header()
    );
    
    input_port #(.FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH), .CURR_X(CURR_X), .CURR_Y(CURR_Y)) 
    ip_north (
        .clk(clk), .rst_n(rst_n),
        .flit_in(north_in_flit), .flit_in_valid(north_in_valid), .flit_in_ready(north_in_ready),
        .flit_out(ip_flit_out[1]), .flit_out_valid(ip_valid_out[1]), .flit_out_ready(ip_ready_out[1]),
        .route_req(ip_route[1]), .is_header()
    );
    
    input_port #(.FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH), .CURR_X(CURR_X), .CURR_Y(CURR_Y)) 
    ip_south (
        .clk(clk), .rst_n(rst_n),
        .flit_in(south_in_flit), .flit_in_valid(south_in_valid), .flit_in_ready(south_in_ready),
        .flit_out(ip_flit_out[2]), .flit_out_valid(ip_valid_out[2]), .flit_out_ready(ip_ready_out[2]),
        .route_req(ip_route[2]), .is_header()
    );
    
    input_port #(.FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH), .CURR_X(CURR_X), .CURR_Y(CURR_Y)) 
    ip_east (
        .clk(clk), .rst_n(rst_n),
        .flit_in(east_in_flit), .flit_in_valid(east_in_valid), .flit_in_ready(east_in_ready),
        .flit_out(ip_flit_out[3]), .flit_out_valid(ip_valid_out[3]), .flit_out_ready(ip_ready_out[3]),
        .route_req(ip_route[3]), .is_header()
    );
    
    input_port #(.FLIT_WIDTH(FLIT_WIDTH), .FIFO_DEPTH(FIFO_DEPTH), .CURR_X(CURR_X), .CURR_Y(CURR_Y)) 
    ip_west (
        .clk(clk), .rst_n(rst_n),
        .flit_in(west_in_flit), .flit_in_valid(west_in_valid), .flit_in_ready(west_in_ready),
        .flit_out(ip_flit_out[4]), .flit_out_valid(ip_valid_out[4]), .flit_out_ready(ip_ready_out[4]),
        .route_req(ip_route[4]), .is_header()
    );
    
    assign req_to_local = {
        (ip_route[4] == 3'b000) ? ip_valid_out[4] : 1'b0,
        (ip_route[3] == 3'b000) ? ip_valid_out[3] : 1'b0,
        (ip_route[2] == 3'b000) ? ip_valid_out[2] : 1'b0,
        (ip_route[1] == 3'b000) ? ip_valid_out[1] : 1'b0,
        (ip_route[0] == 3'b000) ? ip_valid_out[0] : 1'b0
    };
    
    assign req_to_north = {
        (ip_route[4] == 3'b001) ? ip_valid_out[4] : 1'b0,
        (ip_route[3] == 3'b001) ? ip_valid_out[3] : 1'b0,
        (ip_route[2] == 3'b001) ? ip_valid_out[2] : 1'b0,
        (ip_route[1] == 3'b001) ? ip_valid_out[1] : 1'b0,
        (ip_route[0] == 3'b001) ? ip_valid_out[0] : 1'b0
    };
    
    assign req_to_south = {
        (ip_route[4] == 3'b010) ? ip_valid_out[4] : 1'b0,
        (ip_route[3] == 3'b010) ? ip_valid_out[3] : 1'b0,
        (ip_route[2] == 3'b010) ? ip_valid_out[2] : 1'b0,
        (ip_route[1] == 3'b010) ? ip_valid_out[1] : 1'b0,
        (ip_route[0] == 3'b010) ? ip_valid_out[0] : 1'b0
    };
    
    assign req_to_east = {
        (ip_route[4] == 3'b011) ? ip_valid_out[4] : 1'b0,
        (ip_route[3] == 3'b011) ? ip_valid_out[3] : 1'b0,
        (ip_route[2] == 3'b011) ? ip_valid_out[2] : 1'b0,
        (ip_route[1] == 3'b011) ? ip_valid_out[1] : 1'b0,
        (ip_route[0] == 3'b011) ? ip_valid_out[0] : 1'b0
    };
    
    assign req_to_west = {
        (ip_route[4] == 3'b100) ? ip_valid_out[4] : 1'b0,
        (ip_route[3] == 3'b100) ? ip_valid_out[3] : 1'b0,
        (ip_route[2] == 3'b100) ? ip_valid_out[2] : 1'b0,
        (ip_route[1] == 3'b100) ? ip_valid_out[1] : 1'b0,
        (ip_route[0] == 3'b100) ? ip_valid_out[0] : 1'b0
    };
    
    switch_allocator #(.NUM_PORTS(NUM_PORTS)) sa (
        .clk(clk), .rst_n(rst_n),
        .request_local(req_to_local),
        .request_north(req_to_north),
        .request_south(req_to_south),
        .request_east(req_to_east),
        .request_west(req_to_west),
        .grant_local(grant_from_local),
        .grant_north(grant_from_north),
        .grant_south(grant_from_south),
        .grant_east(grant_from_east),
        .grant_west(grant_from_west)
    );
    
    assign ip_ready_out[0] = grant_from_local[0] | grant_from_north[0] | grant_from_south[0] | grant_from_east[0] | grant_from_west[0];
    assign ip_ready_out[1] = grant_from_local[1] | grant_from_north[1] | grant_from_south[1] | grant_from_east[1] | grant_from_west[1];
    assign ip_ready_out[2] = grant_from_local[2] | grant_from_north[2] | grant_from_south[2] | grant_from_east[2] | grant_from_west[2];
    assign ip_ready_out[3] = grant_from_local[3] | grant_from_north[3] | grant_from_south[3] | grant_from_east[3] | grant_from_west[3];
    assign ip_ready_out[4] = grant_from_local[4] | grant_from_north[4] | grant_from_south[4] | grant_from_east[4] | grant_from_west[4];
    
    assign all_flits = {ip_flit_out[4], ip_flit_out[3], ip_flit_out[2], ip_flit_out[1], ip_flit_out[0]};
    
    output_port #(.FLIT_WIDTH(FLIT_WIDTH), .NUM_PORTS(NUM_PORTS)) 
    op_local (
        .clk(clk), .rst_n(rst_n),
        .flit_in_all(all_flits),
        .grant(grant_from_local),
        .flit_out(local_out_flit),
        .flit_out_valid(local_out_valid),
        .flit_out_ready(local_out_ready)
    );
    
    output_port #(.FLIT_WIDTH(FLIT_WIDTH), .NUM_PORTS(NUM_PORTS)) 
    op_north (
        .clk(clk), .rst_n(rst_n),
        .flit_in_all(all_flits),
        .grant(grant_from_north),
        .flit_out(north_out_flit),
        .flit_out_valid(north_out_valid),
        .flit_out_ready(north_out_ready)
    );
    
    output_port #(.FLIT_WIDTH(FLIT_WIDTH), .NUM_PORTS(NUM_PORTS)) 
    op_south (
        .clk(clk), .rst_n(rst_n),
        .flit_in_all(all_flits),
        .grant(grant_from_south),
        .flit_out(south_out_flit),
        .flit_out_valid(south_out_valid),
        .flit_out_ready(south_out_ready)
    );
    
    output_port #(.FLIT_WIDTH(FLIT_WIDTH), .NUM_PORTS(NUM_PORTS)) 
    op_east (
        .clk(clk), .rst_n(rst_n),
        .flit_in_all(all_flits),
        .grant(grant_from_east),
        .flit_out(east_out_flit),
        .flit_out_valid(east_out_valid),
        .flit_out_ready(east_out_ready)
    );
    
    output_port #(.FLIT_WIDTH(FLIT_WIDTH), .NUM_PORTS(NUM_PORTS)) 
    op_west (
        .clk(clk), .rst_n(rst_n),
        .flit_in_all(all_flits),
        .grant(grant_from_west),
        .flit_out(west_out_flit),
        .flit_out_valid(west_out_valid),
        .flit_out_ready(west_out_ready)
    );

endmodule
