#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern int our_code_starts_here() asm("our_code_starts_here");
extern int print(int val) asm("print");

void print_rec(int val) {
  if(val & 0x00000001 ^ 0x00000001) {
    printf("%d", val >> 1);
  }
  else if((val & 0x00000007) == 5) {
    printf("<function>");
  }
  else if(val == 0xFFFFFFFF) {
    printf("true");
  }
  else if(val == 0x7FFFFFFF) {
    printf("false");
  }
  else if((val & 0x00000007) == 1) {
    int* valp = (int*) (val - 1);
    printf("(");
    print_rec(*valp);
    printf(", ");
    print_rec(*(valp + 1));
    printf(")");
  }
  else {
    printf("Unknown value: %#010x", val);
  }
}

int print(int val) {
  print_rec(val);
  printf("\n");
  return val;
}

int main(int argc, char** argv) {
  int* HEAP = calloc(100000, sizeof (int));

  int result = our_code_starts_here(HEAP);
  print(result);
  free(HEAP);
  return 0;
}

