/**
 * MIT License
 *
 * Copyright (c) 2025 Sahil
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * @file cqt.h
 * @brief Header file for Constant-Q Transform (CQT) implementation using sparse
 * kernels and PFFFT.
 */

#ifndef CQT_H_
#define CQT_H_

#include <math.h>

/**
 * @struct Complex
 * @brief Custom structure for representing a single-precision complex number.
 *
 * This structure is used throughout the codebase to represent complex values in
 * a portable, memory-efficient format. The binary layout is compatible with
 * interleaved float arrays.
 */
typedef struct Complex {
    float re; /**< Real part of the complex number */
    float im; /**< Imaginary part of the complex number */
} Complex;

#define SMType Complex

Complex cprod(Complex a, Complex b);
#define SMProd(a, b) cprod(a, b)

Complex csum(Complex a, Complex b);
#define SMSum(a, b) csum(a, b)

void print_complex(Complex a);
#define SM_DBG_PRINT_FN(a) print_complex(a)

#if defined(CQT_DEBUG)
#define SM_DEBUG
#define WIN_DEBUG
#endif // CQT_DEBUG

#include "sparse-matrix.h"

#define WTYPE float

#include "pffft/pffft.h"
#include "window-bank.h"

#if defined(CQT_DEBUG)
#include <assert.h>
#include <stdio.h>
#endif // CQT_DEBUG

/**
 * @brief Forward declaration of SparseMatrix, used to represent sparse CQT
 * kernels.
 */
typedef struct SparseMatrix SparseKernel_t;

/**
 * @struct CQTContext
 * @brief Main context object for holding state and buffers for the Constant-Q
 * Transform.
 *
 * This object holds all precomputed state, memory buffers, and transformation
 * results. It must be initialized using `cqtresult_init()` and cleaned up with
 * `cqtresult_deinit()`.
 */
typedef struct CQTContext {
    int bins;  /**< Number of frequency bins (columns of sparse kernel) */
    int inlen; /**< Padded input length (FFT size) */
    PFFFT_Setup *psetup; /**< FFT setup object (PFFFT handle) */
    float *input;  /**< Input buffer (interleaved real and imaginary floats) */
    float *work;   /**< Scratch space used during FFT */
    float *output; /**< FFT output buffer (same format as input) */
    SparseKernel_t
        *pkernel; /**< Sparse kernel matrix used for applying the CQT */
} CQTContext;

typedef enum ResultStatus { SUCCESS, FAILED, UNINIT } ResultStatus;

typedef struct CQTResult {
    ResultStatus status;
    int bins;
    Vec *prv; // Pointer to the result vector
} CQTResult;

/* === Utility Functions === */

/**
 * @brief Computes the next power of 2 greater than or equal to the given
 * number.
 *
 * Used to determine FFT lengths that are optimal for power-of-2 FFTs.
 *
 * @param n The input number (e.g., signal length).
 * @return The next power of 2, or 0 on overflow or error.
 */
unsigned long nextPow2(unsigned long n);

/**
 * @brief Multiplies two complex numbers using standard formula.
 *
 * Performs (a + ib) * (c + id) = (ac - bd) + i(ad + bc)
 *
 * @param a First complex number.
 * @param b Second complex number.
 * @return The result of complex multiplication.
 */
Complex cprod(Complex a, Complex b);

/**
 * @brief Add two complex numbers.
 *
 * Performs (a.re + i·a.im) + (b.re + i·b.im).
 *
 * @param a First complex number.
 * @param b Second complex number.
 * @return Sum of the two complex numbers.
 */
Complex csum(Complex a, Complex b);

/**
 * @brief Computes the magnitude (absolute value) of a complex number.
 *
 * Uses sqrt(re^2 + im^2) to calculate the magnitude.
 *
 * @param a The complex number.
 * @return The absolute value of the complex number.
 */
float ecqt_abs(Complex a);

/* === Kernel Initialization === */

/**
 * @brief Initializes a sparse kernel matrix for the CQT based on given
 * parameters.
 *
 * This function precomputes a sparse frequency-domain kernel matrix using
 * windowed sinusoids, which are transformed via FFT and thresholded to sparsify
 * the matrix.
 *
 * @param fmin  Minimum frequency to analyze.
 * @param fs    Sampling rate of the input signal.
 * @param b     Number of bins per octave.
 * @param thres Amplitude threshold for sparsity (e.g., 0.0001).
 * @return A pointer to the initialized sparse kernel matrix, or NULL on error.
 */
SparseKernel_t *sparseKernel_init(float fmin, float fs, int b, float thres);

/**
 * @brief Deallocates and frees the memory associated with a sparse kernel
 * matrix.
 *
 * @param psk Pointer to the sparse kernel matrix to deinitialize.
 */
void sparseKernel_deinit(SparseKernel_t *psk);

/* === CQT Transform Operations === */

/**
 * @brief Initializes and allocates memory for a CQTContext structure.
 *
 * This function prepares all internal buffers, FFT setup, and kernel matrix
 * needed to perform the Constant-Q Transform on real-valued input data.
 *
 * @param fmin  Minimum analysis frequency.
 * @param fs    Sampling rate.
 * @param b     Bins per octave.
 * @param thres Threshold for kernel sparsity.
 * @return A pointer to the initialized CQTResult object, or NULL on failure.
 */
CQTContext *cqtcontext_init(float fmin, float fs, int b, float thres);

/**
 * @brief Frees memory and internal structures associated with a CQTContext
 * object.
 *
 * @param pres Pointer to the CQTResult structure to deinitialize.
 */
void cqtcontext_deinit(CQTContext *pcxt);

/**
 * @brief Applies the Constant-Q Transform on the given input signal.
 *
 * The input is expected to be real-valued audio, and will be zero-padded and
 * converted into an interleaved float complex buffer. The result is stored
 * in `pres->result`.
 *
 * @param pres  Initialized CQTResult handle.
 * @param input Input signal buffer (real values).
 * @param size  Length of the input buffer.
 * @return 0 on success, -1 on error.
 */
int cqtcontext_transform(CQTContext *pctx, float *input, int size,
                         CQTResult *pres);

/**
 * @brief Initialize the CQTResult structure
 *
 * It is required to obtain the CQT transform and hold the result vector
 *
 * @param fmin minimum frequency
 * @param fs samping rate
 * @param b number of bins per octave
 * @return Pointer to the structure
 */
CQTResult *cqtresult_init(float fmin, float fs, int b);

/**
 * @brief Deinitialize the CQTResult structure.
 * @param pres Pointer to the CQTResult structure to deinitialize.
 */
void cqtresult_deinit(CQTResult *pres);

// Implementations

SparseKernel_t *sparseKernel_init(float fmin, float fs, int b, float thres) {

    float fmax = fs / 2;
    float Q = 1 / (pow(2.0, 1.0 / b) - 1.0);
    int K = ceil(b * log2(fmax / fmin));
    int N = nextPow2(ceil(Q * fs / fmin)); // FFT length

#if defined(CQT_DEBUG)
    printf("fmax: %.3f\n", fmax);
    printf("Q: %.6f\n", Q);
    printf("K: %d\n", K);
    printf("N: %d\n", N);
#endif

    PFFFT_Setup *fftsetup = pffft_new_setup(N, PFFFT_COMPLEX);
    if (fftsetup == NULL) {
#if defined(CQT_DEBUG)
        printf("pffft setup failed.\n");
#endif
        return NULL;
    }

    float *input = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);
    if (input == NULL) {
#if defined(CQT_DEBUG)
        printf("input buffer setup failed in sparseKernel_init.\n");
#endif
        return NULL;
    }

    float *work = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);
    if (work == NULL) {
        free(input);
#if defined(CQT_DEBUG)
        printf("work buffer setup failed in sparseKernel_init.\n");
#endif
        return NULL;
    }

    float *output = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);
    if (output == NULL) {
        free(input);
        free(work);
#if defined(CQT_DEBUG)
        printf("output buffer setup failed in sparseKernel_init.\n");
#endif
        return NULL;
    }

    SparseKernel_t *psk = sparse_matrix_init(N, K);
    if (psk == NULL) {
#if defined(CQT_DEBUG)
        printf("sparse matrix init failed in sparseKernel_init.\n");
#endif
        return NULL;
    }

    for (int k = K - 1; k >= 0; k--) {
        float fk = fmin * pow(2.0, 1.0 * k / b);
        int Nk = ceil(Q * fs / fk);

        Window *pwin = window_init(Nk, HAMMING);
        if (pwin == NULL) {
            // free the fft buffer
            pffft_aligned_free(input);
            pffft_aligned_free(work);
            pffft_aligned_free(output);

            sparseKernel_deinit(psk);
#if defined(CQT_DEBUG)
            printf("window(%d) init failed in sparseKernel_init.\n", Nk);
#endif
            return NULL;
        }
        // fill the window
        window_fill(pwin);

#if defined(CQT_DEBUG) && defined(WINDOW_CHECKSUM)
        float checksum = 0.0f;
        for (int i = 0; i < pwin->size; i++) {
            checksum += pwin->values[i];
        }
        printf("Window checksum[%d]: %.6f\n", k, checksum);
#endif
        memset(input, 0, sizeof(float) * 2 * N);
        for (int n = 0; n < Nk; n++) {
            float re = pwin->values[n] * cos(2.0 * PI * Q * n / Nk) / Nk;
            float im = pwin->values[n] * sin(2.0 * PI * Q * n / Nk) / Nk;
            input[2 * (n + (N - Nk) / 2)] = re;
            input[2 * (n + (N - Nk) / 2) + 1] = im;
        }

        pffft_transform_ordered(fftsetup, input, output, work, PFFFT_FORWARD);

        for (int n = 0; n < N; n++) {
            Complex z = {output[2 * n], output[2 * n + 1]};
            if (ecqt_abs(z) > thres) {
                // store the scaled conjugate of the complex number
                Complex z_scaled = {z.re / N, -z.im / N};
                sparse_matrix_add_entry(psk, z_scaled, n, k);
            }
        }

        window_deinit(pwin);
    }

    pffft_aligned_free(input);
    pffft_aligned_free(work);
    pffft_aligned_free(output);

    pffft_destroy_setup(fftsetup);
    return psk;
}

void sparseKernel_deinit(SparseKernel_t *psk) { sparse_matrix_deinit(psk); }

CQTContext *cqtcontext_init(float fmin, float fs, int b, float thres) {
    CQTContext *pctx = (CQTContext *)malloc(sizeof(CQTContext));
    if (pctx == NULL) {
#if defined(CQT_DEBUG)
        printf("Memory allocation falied for CQTContext in cqtcontext_init.\n");
#endif
        return NULL;
    }

    float fmax = fs / 2;
    float Q = 1 / (pow(2.0, 1.0 / b) - 1.0);
    int N = nextPow2(ceil(Q * fs / fmin));
    int K = ceil(b * log2(fmax / fmin));

    pctx->bins = K;
    pctx->inlen = N;
    pctx->psetup = pffft_new_setup(N, PFFFT_COMPLEX);
    pctx->pkernel = sparseKernel_init(fmin, fs, b, thres);
    pctx->input = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);
    pctx->work = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);
    pctx->output = (float *)pffft_aligned_malloc(sizeof(float) * 2 * N);

    if (pctx->input == NULL || pctx->work == NULL || pctx->output == NULL ||
        pctx->pkernel == NULL || pctx->psetup == NULL) {
#if defined(CQT_DEBUG)
        printf("some initialization failed during cqtcontext_init.\n");
#endif
        cqtcontext_deinit(pctx);
        return NULL;
    }
    return pctx;
}

void cqtcontext_deinit(CQTContext *pctx) {
    if (pctx) {
        if (pctx->psetup)
            pffft_destroy_setup(pctx->psetup);
        if (pctx->pkernel)
            sparseKernel_deinit(pctx->pkernel);
        if (pctx->input)
            pffft_aligned_free(pctx->input);
        if (pctx->work)
            pffft_aligned_free(pctx->work);
        if (pctx->output)
            pffft_aligned_free(pctx->output);
        free(pctx);
    }
}

int cqtcontext_transform(CQTContext *pctx, float *input, int size,
                         CQTResult *pres) {
    if (input && pres && pctx->psetup && pctx->input && pctx->work &&
        pctx->output && pctx->pkernel && pres && pres->prv &&
        pres->prv->entries) {

        if (pres->bins != pctx->bins) {
#if defined(CQT_DEBUG)
            printf("bin mismatch in cqtcontext_transform.\n");
#endif // CQT_DEBUG
            return -1;
        }

        // pad with trailing zeroes
        memset(pctx->input, 0, sizeof(float) * 2 * pctx->inlen);
        int mnlen = MIN(size, pctx->inlen);
#if defined(CQT_DEBUG)
        printf("the mnlen is: %d\n", mnlen);
#endif
        for (int i = 0; i < mnlen; i++) {
            pctx->input[2 * i] = input[i]; // real signal
            pctx->input[2 * i + 1] = 0.0f;
        }
        pffft_transform_ordered(pctx->psetup, pctx->input, pctx->output,
                                pctx->work, PFFFT_FORWARD);
#if defined(CQT_DEBUG)
        float freq = 0.0f;
        float mx = 0.0f;
        for (int i = 0; i < pctx->inlen / 2; i++) {
            Complex z = {pctx->output[2 * i], pctx->output[2 * i + 1]};
            if (ecqt_abs(z) > mx) {
                freq = i * 44100.0 / pctx->inlen;
                mx = ecqt_abs(z);
            }
        }
        printf("peak-frequency: %.6f Hz\n", freq);

#endif // CQT_DEBUG
        return sparse_matrix_mult_mem_left((Complex *)pctx->output, pctx->inlen,
                                           pctx->pkernel, pres->prv);
    }
#if defined(CQT_DEBUG)
    printf("invalid pointer provided in cqtcontext_transform.\n");
#endif
    return -1;
}

CQTResult *cqtresult_init(float fmin, float fs, int b) {
    float fmax = fs / 2;
    float Q = 1 / (pow(2.0, 1.0 / b) - 1.0);
    int K = ceil(b * log2(fmax / fmin));
    CQTResult *pres = (CQTResult *)malloc(sizeof(CQTResult));
    if (pres == NULL) {
#if defined(CQT_DEBUG)
        printf("Memory allocation failure for CQTResult at cqtresult_init.\n");
#endif
        return NULL;
    }

    pres->bins = K;
    pres->status = UNINIT;
    pres->prv = vec_init(K);
    if (pres->prv == NULL) {
        free(pres);
#if defined(CQT_DEBUG)
        printf("vector initialization failed at cqtresult_init.\n");
#endif
        return NULL;
    }

    return pres;
}

void cqtresult_deinit(CQTResult *pres) {
    if (pres) {
        if (pres->prv) {
            vec_deinit(pres->prv);
        }
        free(pres);
    }
}

unsigned long nextPow2(unsigned long n) {
    int pmsb = -1;
    bool set = false;
    for (int i = 0; i < 32; i++) {
        if ((n << i) & 0x80000000) {
            if (pmsb != -1) {
                set = true;
                break;
            } else {
                pmsb = 31 - i;
            }
        }
    }
    if (pmsb == -1)
        return 0;
    if (!set)
        return n;
    if (pmsb == 31)
        return 0;
    return 1UL << (pmsb + 1);
}

Complex cprod(Complex a, Complex b) {
    Complex prod;
    prod.re = a.re * b.re - a.im * b.im;
    prod.im = a.re * b.im + a.im * b.re;
    return prod;
}

Complex csum(Complex a, Complex b) {
    Complex sum;
    sum.re = a.re + b.re;
    sum.im = a.im + b.im;
    return sum;
}

float ecqt_abs(Complex a) { return sqrt(a.re * a.re + a.im * a.im); }

#if defined(CQT_DEBUG)
void print_complex(Complex a) { printf("%.3f+%.3fi ", a.re, a.im); }
#endif

#endif // CQT_H_
