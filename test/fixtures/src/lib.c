/* Shared object fixture. */
int lib_counter = 5;
const char lib_name[] = "libfix";

int libfn(int x) { return x + lib_counter; }
