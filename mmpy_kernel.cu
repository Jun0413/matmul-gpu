// Matrix multiply device code
#include <assert.h>
#include <math.h>
#include "utils.h"
#include "types.h"

using namespace std;

#define TW_M      BLOCKDIM_Y
#define TW_N      BLOCKDIM_X
#define TW_K      SHM_K
#define SHIFT_M   (TW_M / N_OUT_M)
#define SHIFT_N   (TW_N / N_OUT_N)
#define SHIFT_K   (TW_K / N_OUT_K)

__global__ void matMul(int N, _DOUBLE_ *C, _DOUBLE_ *A, _DOUBLE_ *B) {

    // for linear addressing
    assert(!(TW_M % N_OUT_M));
    assert(!(TW_N % N_OUT_N));
    assert(!(TW_K % N_OUT_K));
    assert(!(SHIFT_K % SHIFT_M));
    assert(!(SHIFT_K % SHIFT_N));

    __shared__ _DOUBLE_ As[TW_M][TW_K], Bs[TW_K][TW_N];

    int ty = threadIdx.y,  tx = threadIdx.x;
    int by = blockIdx.y,   bx = blockIdx.x;
    int I =  by*TW_M + ty, J = bx*TW_N + tx;
    

    _DOUBLE_ Cs[N_OUT_M * N_OUT_N] = {0.};
    const unsigned int N_KK = ((N % TW_K) ? N/TW_K+1 : N/TW_K);

    #pragma unroll
    for(int kk = 0; kk < N_KK; kk++){


        // load As
        #pragma unroll
        for(int j = 0; j < TW_K; j += SHIFT_K){
            #pragma unroll
            for(int i = 0; i < TW_M; i += SHIFT_M){
                #pragma unroll
                for(int l = 0; l < SHIFT_K; l += SHIFT_N){
                    int aj = kk*TW_K + j + tx + l, ai = I + i;
                    As[ty + i][tx + j + l] = (ai<N && aj<N) ? __ldg(&A[ai * N + aj]) : 0.;
                }
            }
        }

        // load Bs
        #pragma unroll
        for(int i = 0; i < TW_K; i += SHIFT_K){
            #pragma unroll
            for(int j = 0; j < TW_N; j += SHIFT_N){
                #pragma unroll
                for(int l = 0; l < SHIFT_K; l += SHIFT_M){
                    int bi = kk*TW_K + ty + i + l, bj = J + j;
                    Bs[ty + i + l][tx + j] = (bi<N && bj<N) ? __ldg(&B[bi * N + bj]) : 0.;
                }
            }
        }

        __syncthreads();
        // compute Cij in each block using SHM
        #pragma unroll
        for(int k = 0; k < TW_K; k++){
            // #pragma unroll
            for(int i = 0; i < N_OUT_M; i++){
                // #pragma unroll
                for(int j = 0; j < N_OUT_N; j++) {
                    Cs[i*N_OUT_N + j] += As[ty + i*SHIFT_M][k] * Bs[k][tx + j*SHIFT_N];
                }
            }
        }
        __syncthreads();
    }

    // #pragma unroll
    for(int i = 0; i < N_OUT_M; ++i){
        // #pragma unroll
        for(int j = 0; j < N_OUT_N; ++j){
            int ci = I + i*SHIFT_M, cj = J + j*SHIFT_N;
            if (ci<N && cj<N){
                C[ci*N + cj] = Cs[i*N_OUT_N + j];
            }
        }
    }
}