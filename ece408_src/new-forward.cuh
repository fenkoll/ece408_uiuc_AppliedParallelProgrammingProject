#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_

#define TILE_WIDTH 16
#define UNROLL_BLOCK_SIZE 512
#define MATRIX_MULTIPLY_BLOCK_SIZE 16

#include <mxnet/base.h>

namespace mxnet
{
namespace op
{

__global__ void unroll_kernel(int C, int H, int W, int K, int B, const float *x, float *x_unroll){
    
    int channel, serial;
    
    int h_unroll, w_unroll;
    int h_base;
    int p,q;
    
    int tx = blockIdx.x * blockDim.x + threadIdx.x;

    int H_out = H - K + 1;
    int W_out = W - K + 1;

    int W_unroll = H_out * W_out;
    int H_unroll = K * K * C;

    int h_out_index, w_out_index;

    #define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
    #define x_unroll3d(i2, i1, i0) x_unroll[(i2) * (H_unroll * W_unroll) + (i1) * W_unroll + i0]

    for(int b = 0; b < B; b++){
        if(tx < C * W_unroll){
            channel = tx / W_unroll;
            serial = tx % W_unroll;
            h_out_index = serial / W_out;
            w_out_index = serial % W_out;
            w_unroll = h_out_index * W_out + w_out_index;
            h_base = channel * K * K;
            for(p = 0; p < K; p++)
                for(q = 0; q < K; q++){
                    h_unroll = h_base + p * K + q;
                    x_unroll3d(b, h_unroll, w_unroll) = x4d(b, channel, h_out_index + p, w_out_index + q);
                }
        }
    }
}

__global__ void matrixMultiply(float *A, float *B, float *C, int numARows,
                               int numAColumns, int numBRows,
                               int numBColumns, int numCRows,
                               int numCColumns, int Block) {
  //@@ Insert code to implement matrix multiplication here
  int Row = blockIdx.y * blockDim.y + threadIdx.y;
  int Col = blockIdx.x * blockDim.x + threadIdx.x;

  #define A2d(i1, i0) A[i1 * numAColumns + i0]
  #define B3d(i2, i1, i0) B[i2 * numBColumns * numBRows + i1 * numBColumns + i0]
  #define C3d(i2, i1, i0) C[i2 * numCColumns * numCRows + i1 * numCColumns + i0]

  for(int b = 0; b < Block; b++){
    if(Row < numARows && Col < numBColumns){
      float pValue = 0;
      for(int k=0; k<numAColumns; k++){
        pValue += A2d(Row,k)*B3d(b,k,Col);
      }
      C3d(b,Row,Col) = pValue;
    }
  }

}

/* 
   This function is called by new-inl.h
   Any code you write should be executed by this function.
   For ECE408, we only expect the float version of the operator to be called, so here we specialize with only floats.
*/
template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> &y, const mshadow::Tensor<gpu, 4, float> &x, const mshadow::Tensor<gpu, 4, float> &w)
{

    // Use mxnet's CHECK_EQ to do assertions.
    // Remove this assertion when you do your implementation!
    //CHECK_EQ(0, 1) << "Remove this line and replace with your implementation";

    // Extract the tensor dimensions into B,M,C,H,W,K
    // ...

    const int B = x.shape_[0];
    const int M = y.shape_[1];
    const int C = x.shape_[1];
    const int H = x.shape_[2];
    const int W = x.shape_[3];
    const int K = w.shape_[3];

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int W_unroll = H_out * W_out;
    int H_unroll = K * K * C;
    int num_threads = C * H_out * W_out;

    float* device_X_unroll;
    cudaMalloc((void**)&device_X_unroll, B * W_unroll * H_unroll * sizeof(float));
    dim3 blockDim1(UNROLL_BLOCK_SIZE,1,1);
    dim3 gridDim1(ceil(num_threads * 1.0/(UNROLL_BLOCK_SIZE)),1,1);    
    
    unroll_kernel<<<gridDim1, blockDim1>>>(C, H, W, K, B, x.dptr_, device_X_unroll);
    int numARows, numAColumns, numBRows, numBColumns, numCRows, numCColumns;

    numBRows = H_unroll;
    numBColumns =  W_unroll;
    numAColumns =  numBRows;
    numARows = M;
    numCRows = numARows;
    numCColumns = numBColumns;

    dim3 blockDim2(ceil(numBColumns*1.0/MATRIX_MULTIPLY_BLOCK_SIZE),ceil(numARows*1.0/MATRIX_MULTIPLY_BLOCK_SIZE),1);
    dim3 gridDim2(MATRIX_MULTIPLY_BLOCK_SIZE,MATRIX_MULTIPLY_BLOCK_SIZE,1);

    matrixMultiply<<<gridDim2,blockDim2>>>(w.dptr_, device_X_unroll, y.dptr_, numARows, numAColumns, numBRows, numBColumns, numCRows, numCColumns, B);

    cudaFree(device_X_unroll);
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());
}

/* 
    This tells mxnet how to do an op when it's not a float.
    This is not used in the ECE408 project
*/
template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}

#endif