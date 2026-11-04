// ============================================================================
// keccak_f1600.sv
// Keccak-f[1600] permutation, one round per clock (24 cycles).
// State is 25 lanes of 64 bit, lane i = x + 5*y, little-endian bytes.
// ============================================================================
package keccak_pkg;

    typedef logic [63:0] lanes_t [25];

    function automatic logic [63:0] rol(input logic [63:0] v, input int n);
        return (n == 0) ? v : ((v << n) | (v >> (64 - n)));
    endfunction

    function automatic logic [63:0] rc(input logic [4:0] r);
        case (r)
            5'd0 : rc = 64'h0000000000000001;
            5'd1 : rc = 64'h0000000000008082;
            5'd2 : rc = 64'h800000000000808A;
            5'd3 : rc = 64'h8000000080008000;
            5'd4 : rc = 64'h000000000000808B;
            5'd5 : rc = 64'h0000000080000001;
            5'd6 : rc = 64'h8000000080008081;
            5'd7 : rc = 64'h8000000000008009;
            5'd8 : rc = 64'h000000000000008A;
            5'd9 : rc = 64'h0000000000000088;
            5'd10: rc = 64'h0000000080008009;
            5'd11: rc = 64'h000000008000000A;
            5'd12: rc = 64'h000000008000808B;
            5'd13: rc = 64'h800000000000008B;
            5'd14: rc = 64'h8000000000008089;
            5'd15: rc = 64'h8000000000008003;
            5'd16: rc = 64'h8000000000008002;
            5'd17: rc = 64'h8000000000000080;
            5'd18: rc = 64'h000000000000800A;
            5'd19: rc = 64'h800000008000000A;
            5'd20: rc = 64'h8000000080008081;
            5'd21: rc = 64'h8000000000008080;
            5'd22: rc = 64'h0000000080000001;
            5'd23: rc = 64'h8000000080008008;
            default: rc = 64'h0;
        endcase
    endfunction

    // one Keccak round: theta, rho, pi, chi, iota
    function automatic lanes_t keccak_round(input lanes_t s, input logic [4:0] r);
        logic [63:0] a [25];
        logic [63:0] b [25];
        logic [63:0] c [5];
        logic [63:0] d [5];
        lanes_t      o;
        for (int i = 0; i < 25; i++) a[i] = s[i];
        // theta
        for (int x = 0; x < 5; x++) c[x] = a[x] ^ a[x+5] ^ a[x+10] ^ a[x+15] ^ a[x+20];
        for (int x = 0; x < 5; x++) d[x] = c[(x+4) % 5] ^ rol(c[(x+1) % 5], 1);
        for (int i = 0; i < 25; i++) a[i] = a[i] ^ d[i % 5];
        // rho + pi
        b[ 0] = rol(a[ 0],  0);
        b[16] = rol(a[ 5], 36);
        b[ 7] = rol(a[10],  3);
        b[23] = rol(a[15], 41);
        b[14] = rol(a[20], 18);
        b[10] = rol(a[ 1],  1);
        b[ 1] = rol(a[ 6], 44);
        b[17] = rol(a[11], 10);
        b[ 8] = rol(a[16], 45);
        b[24] = rol(a[21],  2);
        b[20] = rol(a[ 2], 62);
        b[11] = rol(a[ 7],  6);
        b[ 2] = rol(a[12], 43);
        b[18] = rol(a[17], 15);
        b[ 9] = rol(a[22], 61);
        b[ 5] = rol(a[ 3], 28);
        b[21] = rol(a[ 8], 55);
        b[12] = rol(a[13], 25);
        b[ 3] = rol(a[18], 21);
        b[19] = rol(a[23], 56);
        b[15] = rol(a[ 4], 27);
        b[ 6] = rol(a[ 9], 20);
        b[22] = rol(a[14], 39);
        b[13] = rol(a[19],  8);
        b[ 4] = rol(a[24], 14);
        // chi
        for (int y = 0; y < 5; y++)
            for (int x = 0; x < 5; x++)
                o[x+5*y] = b[x+5*y] ^ (~b[(x+1) % 5 + 5*y] & b[(x+2) % 5 + 5*y]);
        // iota
        o[0] = o[0] ^ rc(r);
        return o;
    endfunction

endpackage
