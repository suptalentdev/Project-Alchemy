pragma solidity ^0.4.2;
import "BLAKE2b/GasTest.sol";
import "BLAKE2b/BLAKE2b_Constants.sol";

contract BLAKE2b is GasTest, BLAKE2_Constants{

  struct BLAKE2b_ctx {
    uint256[4] b; //input buffer
    uint64[8] h;  //chained state
    uint128 t; //total bytes
    uint64 c; //Size of b
    uint outlen; //diigest output size
  }

  // Mixing Function
  function G(uint64[16] v, uint a, uint b, uint c, uint d, uint64 x, uint64 y) constant {

       // Dereference to decrease memory reads
       uint64 va = v[a];
       uint64 vb = v[b];
       uint64 vc = v[c];
       uint64 vd = v[d];

       //Optimised mixing function
       assembly{
         // v[a] := (v[a] + v[b] + x) mod 2**64
         va := addmod(add(va,vb),x, 0x10000000000000000)
         //v[d] := (v[d] ^ v[a]) >>> 32
         vd := xor(div(xor(vd,va), 0x100000000), mulmod(xor(vd, va),0x100000000, 0x10000000000000000))
         //v[c] := (v[c] + v[d])     mod 2**64
         vc := addmod(vc,vd, 0x10000000000000000)
         //v[b] := (v[b] ^ v[c]) >>> 24
         vb := xor(div(xor(vb,vc), 0x1000000), mulmod(xor(vb, vc),0x10000000000, 0x10000000000000000))
         // v[a] := (v[a] + v[b] + y) mod 2**64
         va := addmod(add(va,vb),y, 0x10000000000000000)
         //v[d] := (v[d] ^ v[a]) >>> 16
         vd := xor(div(xor(vd,va), 0x10000), mulmod(xor(vd, va),0x1000000000000, 0x10000000000000000))
         //v[c] := (v[c] + v[d])     mod 2**64
         vc := addmod(vc,vd, 0x10000000000000000)
         // v[b] := (v[b] ^ v[c]) >>> 63
         vb := xor(div(xor(vb,vc), 0x8000000000000000), mulmod(xor(vb, vc),0x2, 0x10000000000000000))
       }

       v[a] = va;
       v[b] = vb;
       v[c] = vc;
       v[d] = vd;
  }


  function compress(BLAKE2b_ctx ctx, bool last) internal {
    //TODO: Look into storing these as uint256[4]
    uint64[16] memory v;
    uint64[16] memory m;


    for(uint i=0; i<8; i++){
      v[i] = ctx.h[i]; // v[:8] = h[:8]
      v[i+8] = IV[i];  // v[8:] = IV
    }

    //
    v[12] = v[12] ^ uint64(ctx.t % 2**64);  //Lower word of t
    v[13] = v[13] ^ uint64(ctx.t / 2**64);

    if(last) v[14] = ~v[14];   //Finalization flag

    uint64 mi;  //Temporary stack variable to decrease memory ops
    uint b; // Input buffer

    for(i = 0; i <16; i++){ //Operate 16 words at a time
      uint k = i%4; //Current buffer word
      mi = 0;
      if(k == 0){
        b=ctx.b[i/4];  //Load relevant input into buffer
      }

      //Extract relevent input from buffer
      assembly{
        mi := and(div(b,exp(2,mul(64,sub(3,k)))), 0xFFFFFFFFFFFFFFFF)
      }

      //Flip endianness
      m[i] = getWords(mi);
    }

    //Mix m
    for(i=0; i<12; i++){
      //TODO: Dereference SIGMA[i]
      G( v, 0, 4, 8, 12, m[SIGMA[i][0]], m[SIGMA[i][1]]);
      G( v, 1, 5, 9, 13, m[SIGMA[i][2]], m[SIGMA[i][3]]);
      G( v, 2, 6, 10, 14, m[SIGMA[i][4]], m[SIGMA[i][5]]);
      G( v, 3, 7, 11, 15, m[SIGMA[i][6]], m[SIGMA[i][7]]);
      G( v, 0, 5, 10, 15, m[SIGMA[i][8]], m[SIGMA[i][9]]);
      G( v, 1, 6, 11, 12, m[SIGMA[i][10]], m[SIGMA[i][11]]);
      G( v, 2, 7, 8, 13, m[SIGMA[i][12]], m[SIGMA[i][13]]);
      G( v, 3, 4, 9, 14, m[SIGMA[i][14]], m[SIGMA[i][15]]);
    }

    //XOR current state with both halves of v
    for(i=0; i<8; ++i){
      ctx.h[i] = ctx.h[i] ^ v[i] ^ v[i+8];
    }

  }


  function init(BLAKE2b_ctx ctx, uint64 outlen, bytes key, uint64[2] salt, uint64[2] person) internal{

      if(outlen == 0 || outlen > 64 || key.length > 64) throw;

      //Initialize chained-state to IV
      for(uint i = 0; i< 8; i++){
        ctx.h[i] = IV[i];
      }

      // Set up parameter block
      ctx.h[0] = ctx.h[0] ^ 0x01010000 ^ shift_left(uint64(key.length), 8) ^ outlen;
      ctx.h[4] = ctx.h[4] ^ salt[0];
      ctx.h[5] = ctx.h[5] ^ salt[1];
      ctx.h[6] = ctx.h[6] ^ person[0];
      ctx.h[7] = ctx.h[7] ^ person[1];

      ctx.outlen = outlen;
      i = key.length;

      //Run hash once with key as input
      if(key.length > 0){
        update(ctx, key);
        ctx.c = 128;
      }
  }


  function update(BLAKE2b_ctx ctx, bytes input) internal {

    for(uint i = 0; i < input.length; i++){
      //If buffer is full, update byte counters and compress
      if(ctx.c == 128){
        ctx.t += ctx.c;
        compress(ctx, false);
        ctx.c = 0;
      }

      //Update temporary counter c
      uint c = ctx.c++;

      // b -> ctx.b
      uint[4] memory b = ctx.b;
      uint8 a = uint8(input[i]);

      // ctx.b[c] = a
      assembly{
        mstore8(add(b,c),a)
      }
    }
  }


  function finalize(BLAKE2b_ctx ctx, uint64[8] out) internal {
    // Add any uncounted bytes
    ctx.t += ctx.c;

    // Compress with finalization flag
    compress(ctx,true);

    //Flip little to big endian and store in output buffer
    for(uint i=0; i < ctx.outlen / 8; i++){
      out[i] = getWords(ctx.h[i]);
    }

    //Properly pad output if it doesn't fill a full word
    if(ctx.outlen < 64){
      out[ctx.outlen/8] = shift_right(getWords(ctx.h[ctx.outlen/8]),64-8*(ctx.outlen%8));
    }

  }

  //Helper function for full hash function
  function blake2b(bytes input, bytes key, bytes salt, bytes personalization, uint64 outlen) constant public returns(uint64[8]){

    BLAKE2b_ctx memory ctx;
    uint64[8] memory out;

    init(ctx, outlen, key, formatInput(salt), formatInput(personalization));
    update(ctx, input);
    finalize(ctx, out);
    return out;
  }

  function blake2b(bytes input, bytes key, uint64 outlen) constant returns (uint64[8]){
    return blake2b(input, key, "", "", outlen);
  }

// Utility functions

  //Flips endianness of words
  function getWords(uint64 a) constant returns (uint64 b) {
    return  (a & MASK_0) / SHIFT_0 ^
            (a & MASK_1) / SHIFT_1 ^
            (a & MASK_2) / SHIFT_2 ^
            (a & MASK_3) / SHIFT_3 ^
            (a & MASK_4) * SHIFT_3 ^
            (a & MASK_5) * SHIFT_2 ^
            (a & MASK_6) * SHIFT_1 ^
            (a & MASK_7) * SHIFT_0;
  }

  function shift_right(uint64 a, uint shift) constant returns(uint64 b){
    return uint64(a / 2**shift);
  }

  function shift_left(uint64 a, uint shift) constant returns(uint64){
    return uint64((a * 2**shift) % (2**64));
  }

  //bytes -> uint64[2]
  function formatInput(bytes input) constant returns (uint64[2] output){
    for(uint i = 0; i<input.length; i++){
        output[i/8] = output[i/8] ^ shift_left(uint64(input[i]), 64-8*(i%8+1));
    }
        output[0] = getWords(output[0]);
        output[1] = getWords(output[1]);
  }

  function formatOutput(uint64[8] input) constant returns(bytes32[2]){
    bytes32[2] memory result;

    for(uint i = 0; i < 8; i++){
        result[i/4] = result[i/4] ^ bytes32(input[i] * 2**(64*(3-i%4)));
    }
    return result;
  }
}
