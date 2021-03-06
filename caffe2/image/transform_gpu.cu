/**
 * Copyright (c) 2016-present, Facebook, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "caffe2/core/context_gpu.h"
#include "caffe2/image/transform_gpu.h"
#include "caffe2/utils/conversions.h"

/**
 *
 * Copyright (c) 2016, NVIDIA CORPORATION, All rights reserved
 * Distributed under 2-clause BSD license; see accompanying LICENSE file
 *
 **/

namespace caffe2 {

namespace {

// input in (int8, NHWC), output in (fp32, NCHW)
template <typename In, typename Out>
__global__ void transform_kernel(
    const int N,
    const int C,
    const int H,
    const int W,
    const float* mean,
    const float* std,
    const In* in,
    Out* out) {
  const int n = blockIdx.x;

  const int nStride = C*H*W;

  // pointers to data for this image
  const In* input_ptr = &in[n*nStride];
  Out* output_ptr = &out[n*nStride];

  // either read or write uncoalesced - try reading
  for (int c=0; c < C; ++c) {
    for (int h=threadIdx.y; h < H; h += blockDim.y) {
      for (int w=threadIdx.x; w < W; w += blockDim.x) {
        int in_idx = c + C*w + C*W*h;  // HWC
        int out_idx = c*H*W + h*W + w;  // CHW

        output_ptr[out_idx] = convert::To<float,Out>(
          (convert::To<In,float>(input_ptr[in_idx])-mean[c]) * std[c]);
      }
    }
  }
}

}

template <typename T_IN, typename T_OUT, class Context>

bool TransformOnGPU(Tensor<Context>& X, Tensor<Context> *Y,
                    Tensor<Context>& mean, Tensor<Context>& std,
                    Context *context) {
  // data comes in as NHWC
  const int N = X.dim32(0), C = X.dim32(3), H = X.dim32(1), W = X.dim32(2);
  // data goes out as NCHW
  Y->Resize(std::vector<int>{N,C,H,W});

  auto* input_data = X.template data<T_IN>();
  auto* output_data = Y->template mutable_data<T_OUT>();

  transform_kernel<
    T_IN, T_OUT><<<N, dim3(16, 16), 0, context->cuda_stream()>>>(
      N, C, H, W, mean.template data<float>(), std.template data<float>(),
      input_data, output_data);
  return true;
};

template bool TransformOnGPU<uint8_t, float, CUDAContext>(Tensor<CUDAContext>& X,
                                                          Tensor<CUDAContext> *Y,
                                                          Tensor<CUDAContext>& mean,
                                                          Tensor<CUDAContext>& std,
                                                          CUDAContext *context);

template bool TransformOnGPU<uint8_t, float16, CUDAContext>(Tensor<CUDAContext>& X,
                                                            Tensor<CUDAContext> *Y,
                                                            Tensor<CUDAContext>& mean,
                                                            Tensor<CUDAContext>& std,
                                                            CUDAContext *context);

}  // namespace caffe2
