//https://github.com/patrickmcewen/asst3/blob/young/scan/scan.cu
#include <stdio.h>

#include <cuda.h>
#include <cuda_runtime.h>

#include <driver_functions.h>

#include <thrust/scan.h>
#include <thrust/device_ptr.h>
#include <thrust/device_malloc.h>
#include <thrust/device_free.h>

#include "CycleTimer.h"

#include "cuda_runtime.h"             //Includes blockIdx, blockDim, threadIdx and etc.
#include "device_launch_parameters.h" //Includes blockIdx, blockDim, threadIdx and etc.

#define THREADS_PER_BLOCK 256

int find_repeats(int* device_input, int length, int* device_output);

// helper function to round an integer up to the next power of 2
static inline int nextPow2(int n) {
    n--;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n++;
    return n;
}

// exclusive_scan --
//
// Implementation of an exclusive scan on global memory array `input`,
// with results placed in global memory `result`.
//
// N is the logical size of the input and output arrays, however
// students can assume that both the start and result arrays we
// allocated with next power-of-two sizes as described by the comments
// in cudaScan().  This is helpful, since your parallel scan
// will likely write to memory locations beyond N, but of course not
// greater than N rounded up to the next power of 2.
//
// Also, as per the comments in cudaScan(), you can implement an
// "in-place" scan, since the timing harness makes a copy of input and
// places it in result

__global__ void upsweep_kernel(int* result, int N, int two_dplus1, int two_d) {
    int index = two_dplus1 * (blockIdx.x * blockDim.x + threadIdx.x);
    if (index + two_dplus1 - 1 >= N) return;
    //printf("%d ", index + two_dplus1-1);
    result[index + two_dplus1 - 1] += result[index + two_d - 1];
}

__global__ void downsweep_kernel(int* result, int N, int two_dplus1, int two_d) {
    int index = two_dplus1 * (blockIdx.x * blockDim.x + threadIdx.x);
    if (index + two_dplus1 - 1 >= N) return;
    //printf("%d ", index + two_dplus1-1);
    int t = result[index + two_d - 1];
    result[index + two_d - 1] = result[index + two_dplus1 - 1];
    result[index + two_dplus1 - 1] += t;

}

__global__ void zero_last_elem(int* result, int N) {
    int index = (blockIdx.x * blockDim.x + threadIdx.x);
    if (index == 0) {
        result[N - 1] = 0;
    }
}

void exclusive_scan(int* input, int N, int* result)
{

    // CS149 TODO:
    //
    // Implement your exclusive scan implementation here.  Keep in
    // mind that although the arguments to this function are device
    // allocated arrays, this is a function that is running in a thread
    // on the CPU.  Your implementation will need to make multiple calls
    // to CUDA kernel functions (that you must write) to implement the
    // scan.
    N = nextPow2(N);
    int arrSize = sizeof(float) * N;

    cudaMemcpy(result, input, arrSize, cudaMemcpyDeviceToDevice);
    //printf("copied memory from input to result\n");
    for (int two_d = 1; two_d <= N / 2; two_d *= 2) {
        int two_dplus1 = 2 * two_d;
        int numThreads = N / two_dplus1;
        dim3 numBlocks((numThreads + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK);
        dim3 threadsPerBlock((numThreads + numBlocks.x - 1) / numBlocks.x);
        upsweep_kernel << <numBlocks, threadsPerBlock >> > (result, N, two_dplus1, two_d);
        cudaDeviceSynchronize();
        //printf("finished one upsweep\n");
    }
    zero_last_elem << <1, 1 >> > (result, N);
    cudaDeviceSynchronize();
    //printf("finished upsweep, starting downsweep\n");
    for (int two_d = N / 2; two_d >= 1; two_d /= 2) {
        int two_dplus1 = 2 * two_d;
        int numThreads = N / two_dplus1;
        dim3 numBlocks((numThreads + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK);
        dim3 threadsPerBlock((numThreads + numBlocks.x - 1) / numBlocks.x);
        downsweep_kernel << <numBlocks, threadsPerBlock >> > (result, N, two_dplus1, two_d);
        cudaDeviceSynchronize();
        //printf("finished one downsweep\n");
    }
    //printf("finished downsweep\n");

}


//
// cudaScan --
//
// This function is a timing wrapper around the student's
// implementation of scan - it copies the input to the GPU
// and times the invocation of the exclusive_scan() function
// above. Students should not modify it.
double cudaScan(int* inarray, int* end, int* resultarray)
{
    int* device_result;
    int* device_input;
    int N = end - inarray;

    // This code rounds the arrays provided to exclusive_scan up
    // to a power of 2, but elements after the end of the original
    // input are left uninitialized and not checked for correctness.
    //
    // Student implementations of exclusive_scan may assume an array's
    // allocated length is a power of 2 for simplicity. This will
    // result in extra work on non-power-of-2 inputs, but it's worth
    // the simplicity of a power of two only solution.

    int rounded_length = nextPow2(end - inarray);

    cudaMalloc((void**)&device_result, sizeof(int) * rounded_length);
    cudaMalloc((void**)&device_input, sizeof(int) * rounded_length);

    // For convenience, both the input and output vectors on the
    // device are initialized to the input values. This means that
    // students are free to implement an in-place scan on the result
    // vector if desired.  If you do this, you will need to keep this
    // in mind when calling exclusive_scan from find_repeats.
    cudaMemcpy(device_input, inarray, (end - inarray) * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(device_result, inarray, (end - inarray) * sizeof(int), cudaMemcpyHostToDevice);

    double startTime = CycleTimer::currentSeconds();

    // code to test find_repeats on small inputs
    //int result = find_repeats(device_input, N, device_result);
    //printf("result: %d\n", result); 
    exclusive_scan(device_input, N, device_result);

    // Wait for completion
    cudaDeviceSynchronize();
    double endTime = CycleTimer::currentSeconds();

    cudaMemcpy(resultarray, device_result, (end - inarray) * sizeof(int), cudaMemcpyDeviceToHost);

    double overallDuration = endTime - startTime;
    return overallDuration;
}


// cudaScanThrust --
//
// Wrapper around the Thrust library's exclusive scan function
// As above in cudaScan(), this function copies the input to the GPU
// and times only the execution of the scan itself.
//
// Students are not expected to produce implementations that achieve
// performance that is competition to the Thrust version, but it is fun to try.
double cudaScanThrust(int* inarray, int* end, int* resultarray) {

    int length = end - inarray;
    thrust::device_ptr<int> d_input = thrust::device_malloc<int>(length);
    thrust::device_ptr<int> d_output = thrust::device_malloc<int>(length);

    cudaMemcpy(d_input.get(), inarray, length * sizeof(int), cudaMemcpyHostToDevice);

    double startTime = CycleTimer::currentSeconds();

    thrust::exclusive_scan(d_input, d_input + length, d_output);

    cudaDeviceSynchronize();
    double endTime = CycleTimer::currentSeconds();

    cudaMemcpy(resultarray, d_output.get(), length * sizeof(int), cudaMemcpyDeviceToHost);

    thrust::device_free(d_input);
    thrust::device_free(d_output);

    double overallDuration = endTime - startTime;
    return overallDuration;
}


__global__ void mark_repeats(int* input, int* output, int length) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index < length - 1) {
        output[index] = input[index] == input[index + 1];
    }
    else if (index == length - 1) {
        output[length - 1] = 0;
    }
}

__global__ void get_repeats_final(int* input, int* output, int length) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index < length - 1 && (input[index] < input[index + 1])) {
        output[input[index]] = index;
    }
}

__global__ void get_total_pairs(int* input, int length, int* total_pairs) {
    total_pairs[0] = input[length - 1];
}

// find_repeats --
//
// Given an array of integers `device_input`, returns an array of all
// indices `i` for which `device_input[i] == device_input[i+1]`.
//
// Returns the total number of pairs found
int find_repeats(int* device_input, int length, int* device_output) {

    // CS149 TODO:
    //
    // Implement this function. You will probably want to
    // make use of one or more calls to exclusive_scan(), as well as
    // additional CUDA kernel launches.
    //    
    // Note: As in the scan code, the calling code ensures that
    // allocated arrays are a power of 2 in size, so you can use your
    // exclusive_scan function with them. However, your implementation
    // must ensure that the results of find_repeats are correct given
    // the actual array length.

    int length_2 = nextPow2(length);
    int arrSize = length_2 * sizeof(int);

    int* flags = nullptr;
    int* flag_scan = nullptr;
    cudaMalloc(&flags, arrSize);
    cudaMalloc(&flag_scan, arrSize);

    dim3 numBlocks((int)std::ceil((double)length / THREADS_PER_BLOCK));
    dim3 threadsPerBlock((int)std::ceil((double)length / numBlocks.x));
    //printf("%d blocks with %d threads per block\n", numBlocks.x, threadsPerBlock.x);

    mark_repeats << <numBlocks, threadsPerBlock >> > (device_input, flags, length);
    cudaDeviceSynchronize();

    /*int* host_flags = (int*)malloc(arrSize);
    cudaMemcpy(host_flags, flags, arrSize, cudaMemcpyDeviceToHost);
    for (int i = 0; i < length; i++) {
        printf("%d ", host_flags[i]);
    }
    printf("\n");*/

    exclusive_scan(flags, length, flag_scan);
    cudaDeviceSynchronize();

    /*int* host_flags_scan = (int*)malloc(arrSize);
    cudaMemcpy(host_flags_scan, flag_scan, arrSize, cudaMemcpyDeviceToHost);
    for (int i = 0; i < length; i++) {
        printf("%d ", host_flags_scan[i]);
    }
    printf("\n");*/

    int* total_pairs = nullptr;
    cudaMalloc(&total_pairs, sizeof(int));
    get_total_pairs << <1, 1 >> > (flag_scan, length, total_pairs);
    cudaDeviceSynchronize();

    int* total_pairs_host = (int*)malloc(sizeof(int));
    cudaMemcpy(total_pairs_host, total_pairs, sizeof(int), cudaMemcpyDeviceToHost);

    get_repeats_final << <numBlocks, threadsPerBlock >> > (flag_scan, device_output, length);
    cudaDeviceSynchronize();

    /*int* host_output = (int*)malloc(arrSize);
    cudaMemcpy(host_output, device_output, arrSize, cudaMemcpyDeviceToHost);
    for (int i = 0; i < length; i++) {
        printf("%d ", host_output[i]);
    }
    printf("\n");*/

    cudaFree(flags);
    cudaFree(flag_scan);


    return *total_pairs_host;
}


//
// cudaFindRepeats --
//
// Timing wrapper around find_repeats. You should not modify this function.
double cudaFindRepeats(int* input, int length, int* output, int* output_length) {

    int* device_input;
    int* device_output;
    int rounded_length = nextPow2(length);

    cudaMalloc((void**)&device_input, rounded_length * sizeof(int));
    cudaMalloc((void**)&device_output, rounded_length * sizeof(int));
    cudaMemcpy(device_input, input, length * sizeof(int), cudaMemcpyHostToDevice);

    cudaDeviceSynchronize();
    double startTime = CycleTimer::currentSeconds();

    int result = find_repeats(device_input, length, device_output);

    cudaDeviceSynchronize();
    double endTime = CycleTimer::currentSeconds();

    // set output count and results array
    *output_length = result;
    cudaMemcpy(output, device_output, length * sizeof(int), cudaMemcpyDeviceToHost);

    cudaFree(device_input);
    cudaFree(device_output);

    float duration = endTime - startTime;
    return duration;
}



void printCudaInfo()
{
    int deviceCount = 0;
    cudaError_t err = cudaGetDeviceCount(&deviceCount);

    printf("---------------------------------------------------------\n");
    printf("Found %d CUDA devices\n", deviceCount);

    for (int i = 0; i < deviceCount; i++)
    {
        cudaDeviceProp deviceProps;
        cudaGetDeviceProperties(&deviceProps, i);
        printf("Device %d: %s\n", i, deviceProps.name);
        printf("   SMs:        %d\n", deviceProps.multiProcessorCount);
        printf("   Global mem: %.0f MB\n",
            static_cast<float>(deviceProps.totalGlobalMem) / (1024 * 1024));
        printf("   CUDA Cap:   %d.%d\n", deviceProps.major, deviceProps.minor);
    }
    printf("---------------------------------------------------------\n");
}