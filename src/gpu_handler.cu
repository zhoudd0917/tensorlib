#include <cmath>
#include <tensorlib/gpu_handler.cuh>
#include <tensorlib/utils.hpp>

GPUHandler& GPUHandler::getInstance() {
  static GPUHandler instance;
  return instance;
}

void GPUHandler::add(const float* x, const float* y, float* z, size_t size) {
  cublasHandle_t handle = getInstance().getHandle();
  float alpha = 1.0;
  checkCudaErrors(
      cudaMemcpy(z, y, size * sizeof(float), cudaMemcpyDeviceToDevice));
  checkCublasErrors(cublasSaxpy(handle, size, &alpha, x, 1, z, 1));
}

void GPUHandler::sub(const float* x, const float* y, float* z, size_t size) {
  cublasHandle_t handle = getInstance().getHandle();
  float alpha = -1.0f;

  checkCudaErrors(
      cudaMemcpy(z, x, size * sizeof(float), cudaMemcpyDeviceToDevice));
  checkCublasErrors(cublasSaxpy(handle, size, &alpha, y, 1, z, 1));
}

void GPUHandler::multiply(const float* x, const float* y, float* z,
                          size_t size) {
  cublasHandle_t handle = getInstance().getHandle();
  cublasSideMode_t mode = CUBLAS_SIDE_LEFT;

  int m = size, n = 1, lda = size, incx = 1, ldc = size;

  // Perform element-wise multiplication: z = diag(y) * x
  checkCublasErrors(cublasSdgmm(handle, mode, m, n, x, lda, y, incx, z, ldc));
}

__global__ void elementWiseDivision(const float* x, const float* y, float* z,
                                    size_t size) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < size) {
    z[idx] = x[idx] / y[idx];  // Perform element-wise division
  }
}

void GPUHandler::divide(const float* x, const float* y, float* z, size_t size) {
  // Each thread processes one element; set the CUDA grid size
  int blockSize = 256;
  int gridSize = (size + blockSize - 1) / blockSize;

  // Launch the CUDA kernel to perform element-wise division
  elementWiseDivision<<<gridSize, blockSize>>>(x, y, z, size);

  // Check for CUDA errors
  checkCudaErrors(cudaDeviceSynchronize());
}

// helper method for SubBackward
void GPUHandler::axpy(const float* x, float* y, float alpha, size_t size) {
  cublasHandle_t handle = getInstance().getHandle();
  checkCublasErrors(cublasSaxpy(handle, size, &alpha, x, 1, y, 1));
}

// matrix multiplication
void GPUHandler::matmul(const float* X, const float* Y, float* Z, size_t B,
                        size_t M, size_t K, size_t N, bool transX,
                        bool transY) {
  cublasHandle_t handle = getInstance().getHandle();

  auto trans_x = transX ? CUBLAS_OP_T : CUBLAS_OP_N,
       trans_y = transY ? CUBLAS_OP_T : CUBLAS_OP_N;

  // Perform matrix multiplication for each batch
  size_t stride_X = M * K, stride_Y = K * N, stride_Z = M * N;
  const float alpha = 1.0f;
  const float beta = 0.0f;

  // Call cuBLAS gemm function for batch computation
  checkCublasErrors(cublasSgemmStridedBatched(
      handle, trans_y, trans_x, N, M, K, &alpha, Y, (transY ? K : N), stride_Y,
      X, (transX ? M : K), stride_X, &beta, Z, N, stride_Z, B));
}

void GPUHandler::transpose(const float* input, float* output, size_t B,
                           size_t M, size_t N) {
  cublasHandle_t handle = getInstance().getHandle();
  const float alpha = 1.0f;
  const float beta = 0.0f;

  for (size_t b = 0; b < B; ++b) {
    checkCublasErrors(cublasSgeam(handle, CUBLAS_OP_T, CUBLAS_OP_N, M, N,
                                  &alpha, input + b * M * N, N, &beta,
                                  input + b * M * N, M, output + b * M * N, M));
  }
}

__global__ void elementWiseLog(const float* input, float* output, size_t size) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < size) {
    output[idx] = logf(input[idx]);  // Compute natural logarithm (base e)
  }
}

void GPUHandler::log(const float* input, float* output, size_t size) {
  // Each thread processes one element; set the CUDA grid size
  int blockSize = 256;
  int gridSize = (size + blockSize - 1) / blockSize;

  // Launch the CUDA kernel to perform element-wise logarithm
  elementWiseLog<<<gridSize, blockSize>>>(input, output, size);

  // Check for CUDA errors
  checkCudaErrors(cudaDeviceSynchronize());
}

__global__ void elementWiseLog(const float* input, float* output, size_t size) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < size) {
    output[idx] = logf(input[idx]);  // Compute natural logarithm (base e)
  }
}

void GPUHandler::log(const float* input, float* output, size_t size) {
  // Each thread processes one element; set the CUDA grid size
  int blockSize = 256;
  int gridSize = (size + blockSize - 1) / blockSize;

  // Launch the CUDA kernel to perform element-wise logarithm
  elementWiseLog<<<gridSize, blockSize>>>(input, output, size);

  // Check for CUDA errors
  checkCudaErrors(cudaDeviceSynchronize());
}

__global__ void selectIdx(float* X, float* Z, size_t size, size_t idx) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < size) {
    Z[i] = X[i + idx * size];
  }
}

void GPUHandler::select_idx(float* X, float* Z, std::vector<size_t> x_shape,
                            size_t idx) {
  size_t size = calculate_size(x_shape) / x_shape[0];

  int blockSize = 256;
  int gridSize = (size + blockSize - 1) / blockSize;

  selectIdx<<<gridSize, blockSize>>>(X, Z, size, idx);

  checkCudaErrors(cudaDeviceSynchronize());
}