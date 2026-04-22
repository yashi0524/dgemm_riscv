#include <stdio.h>
#include <stdlib.h>

#include "utils.h"

// Matrix dimensions
#define M 4
#define N 4
#define K 4

void scalar_dgemm(int , int , int , 
                  double , const double *, int ,
                  const double *, int ,
                  double , double *, int ) __attribute__((noinline));

/**
 * Scalar DGEMM: C = alpha*(A*B) + beta*C
 * Optimized with i-k-j loop order for better cache locality.
 */
void scalar_dgemm(int m, int n, int k, 
                  double alpha, const double *A, int lda,
                  const double *B, int ldb,
                  double beta, double *C, int ldc)
{
    for (int i = 0; i < m; ++i) {
        // Step 1: Scale existing C by beta
        for (int j = 0; j < n; ++j) {
            C[i * ldc + j] *= beta;
        }

        // Step 2: Accumulate alpha * A * B
        for (int l = 0; l < k; ++l) {
            double temp_a = alpha * A[i * lda + l];
            for (int j = 0; j < n; ++j) {
                C[i * ldc + j] += temp_a * B[l * ldb + j];
            }
        }
    }
}

void print_matrix(const char *name, double *mat, int rows, int cols) {
    printf("Matrix %s:\n", name);
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            printf("%6.1f ", mat[i * cols + j]);
        }
        printf("\n");
    }
    printf("\n");
}

int main() {
    // Static allocation for simplicity in embedded/sim environment
    double A[M * K] = {
        1.0, 2.0, 3.0, 4.0,
        5.0, 6.0, 7.0, 8.0,
        9.0, 8.0, 7.0, 6.0,
        5.0, 4.0, 3.0, 2.0
    };

    double B[K * N] = {
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    };

    double C[M * N] = {0}; // Initialize C with zeros

    double alpha = 1.0;
    double beta = 0.0;

    printf("Starting Scalar DGEMM...\n\n");

    //read_cycle( cycle_count);
    cycle_count = READ_CSR(cycle);

    scalar_dgemm(M, N, K, alpha, A, K, B, N, beta, C, N);

    cycle_count = READ_CSR(cycle) - cycle_count;

    print_matrix("A", A, M, K);
    print_matrix("B", B, K, N);
    print_matrix("C (Result)", C, M, N);

    printf("mcycle = %llu\n", cycle_count);


    return 0;
}