use strict; use DynaLoader;
my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die "load: " . DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, "nd_main") or die "sym";
DynaLoader::dl_install_xsub("main::nd_main", $sym);
nd_main();
