// The task / mesh pipeline prewarm (nvn_mtl.m): the M row mtk_pso writes for a pipeline a draw built, read back as the next start reads its prewarm lists (warm_parse, warm_task),
// is handed to the draws' table under the key a draw looks it up by (warm_claim: the draw then builds nothing); the task shader for a mesh shader is a recorded row's, else the
// nearest before it in its package file, one of its payload's size first, then one of a larger size, and a mesh shader whose payload size no task shader has still gets one
// (mpw_task: none only when no task shader loads, and its pairs are counted apart); the profile's mesh and pixel pairs are built once (mesh_prewarm), a pair whose pixel shader
// has no library is skipped, and the stamp makes the next start return at once. Synthetic shaders in a temporary library folder, no game files
#include "../nvn/nvn_mtl.m"
#include <stdlib.h>
#include <unistd.h>

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static int checks, failed;
#define EXPECT(name, want, got) do { long long w_ = (long long)(want), g_ = (long long)(got); checks++; \
    if (w_ != g_) { fprintf(stderr, "FAIL %s: expected %lld, got %lld\n", name, w_, g_); failed++; } } while (0)
static void require(int ok, const char *name) { EXPECT(name, 1, ok); if (!ok) exit(2); }

// task shaders: TK before the mesh shader with its payload's size, TX nearer before it with another, TA after it with its size; mesh shader MK; pixel shaders FK, and FX without a library;
// mesh shader MK2, after TA, with a payload size (8) no task shader has: TA nearest before it with a smaller one, TX before that with a larger one
#define TK "a0a0a0a0a0a0a0a1"
#define TX "a0a0a0a0a0a0a0a2"
#define TA "a0a0a0a0a0a0a0a3"
#define MK "b0b0b0b0b0b0b0b1"
#define MK2 "b0b0b0b0b0b0b0b2"
#define FK "c0c0c0c0c0c0c0c1"
#define FX "c0c0c0c0c0c0c0c2"
static NSString *g_dir;
static void put(NSString *name, NSString *text) { require([text writeToFile:[g_dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil], name.UTF8String); }

static void fixtures(void) {
    put(@"fixture.metal", @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct V { float4 position [[position]]; }; struct Payload { uint first; };\n"
        "using Mesh = metal::mesh<V, void, 3, 1, metal::topology::triangle>;\n"
        "[[object]] void task(object_data Payload& p [[payload]], mesh_grid_properties grid, uint tid [[thread_index_in_threadgroup]]) {\n"
        "  if (!tid) { p.first = 1; grid.set_threadgroups_per_grid(uint3(1)); } }\n"
        "[[mesh]] void mesh_main(Mesh m, const object_data Payload& p [[payload]], uint tid [[thread_index_in_threadgroup]]) { if (tid) return; float z = float(p.first) * 0.125f;\n"
        "  m.set_vertex(0, V{float4(-1,-1,z,1)}); m.set_vertex(1, V{float4(3,-1,z,1)}); m.set_vertex(2, V{float4(-1,3,z,1)});\n"
        "  m.set_index(0,0); m.set_index(1,1); m.set_index(2,2); m.set_primitive_count(1); }\n"
        "fragment float4 color() { return float4(0,1,0,1); }\n");
    NSString *lib = [g_dir stringByAppendingPathComponent:@"fixture.metallib"];
    NSTask *cc = [NSTask new]; cc.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcrun"];
    cc.arguments = @[@"-sdk", @"macosx", @"metal", [g_dir stringByAppendingPathComponent:@"fixture.metal"], @"-o", lib];
    require([cc launchAndReturnError:nil], "the fixture compiler starts"); [cc waitUntilExit]; require(cc.terminationStatus == 0, "the fixture shaders compile");
    NSDictionary *shaders = @{@TK: @[@"task", @{@"kind": @"ts", @"threads": @32, @"payload": @4}], @TX: @[@"task", @{@"kind": @"ts", @"threads": @32, @"payload": @64}],
                              @TA: @[@"task", @{@"kind": @"ts", @"threads": @32, @"payload": @4}],
                              @MK: @[@"mesh_main", @{@"kind": @"ms", @"threads": @32, @"payload": @4, @"task": @YES}],
                              @MK2: @[@"mesh_main", @{@"kind": @"ms", @"threads": @32, @"payload": @8, @"task": @YES}], @FK: @[@"color", NSNull.null]};
    for (NSString *key in shaders) {
        NSMutableDictionary *j = [@{@"chain": @DMSH_CHAIN, @"route": @"B", @"entry": shaders[key][0], @"bindings": @[], @"vertex_inputs": @[]} mutableCopy];
        if (shaders[key][1] != NSNull.null) j[@"mesh_stage"] = shaders[key][1];
        NSString *base = [g_dir stringByAppendingPathComponent:[key stringByAppendingString:@"_b"]];
        require([[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] writeToFile:[base stringByAppendingString:@".json"] atomically:YES], "a fixture reflection is written");
        require([NSFileManager.defaultManager copyItemAtPath:lib toPath:[base stringByAppendingString:@".metallib"] error:nil], "a fixture library is copied");
    }
    put(@"shader_map.tsv", @"# fixture\npackage\tindex\tstage\tdm_ctl_sha16\tsource\n"
        "t.bin\t0\ttask\t" TK "\t/P.bfsha#BNSH@0x1000#var0\nt.bin\t1\ttask\t" TX "\t/P.bfsha#BNSH@0x2000#var0\nm.bin\t0\tmesh\t" MK "\t/P.bfsha#BNSH@0x2000#var1\n"
        "t.bin\t2\ttask\t" TA "\t/P.bfsha#BNSH@0x3000#var0\np.bin\t0\tpixel\t" FK "\t/P.bfsha#BNSH@0x2000#var1\np.bin\t1\tpixel\t" FX "\t/P.bfsha#BNSH@0x2000#var2\n"
        "m.bin\t1\tmesh\t" MK2 "\t/P.bfsha#BNSH@0x3000#var1\n");
    put(@"shader_pairs.tsv", @MK "\t" FK "\n" MK "\t" FX "\n" MK2 "\t" FK "\n");
    g_msl_dir = g_dir; g_shmap_path = [g_dir stringByAppendingPathComponent:@"shader_map.tsv"];
    g_shmap = [@{@TK: @"task", @TX: @"task", @TA: @"task", @MK: @"mesh", @MK2: @"mesh", @FK: @"pixel", @FX: @"pixel"} mutableCopy];
}

int main(void) { @autoreleasepool {
    char tmpl[] = "/tmp/t_mesh_prewarm.XXXXXX"; require(mkdtemp(tmpl) != NULL, "a temporary folder");
    g_dir = @(tmpl);
    NSString *user = [g_dir stringByAppendingPathComponent:@"pso_user.tsv"];
    setenv("DM_PSO_USER", user.UTF8String, 1); unsetenv("DM_SAVE"); unsetenv("DM_PSO_RECORD"); unsetenv("DM_MESH_PREWARM");
    mtl_init(); fixtures();

    // A draw's first use: mtk_pso builds the pipeline and records its M row
    NvShader *ts = shader_load(@TK "_b", 3, 0), *ms = shader_load(@MK "_b", 4, 0), *fs = shader_load(@FK "_b", 1, 0);
    require(ts && ms && fs && ts->mesh_kind == 1 && ms->mesh_kind == 2 && !ms->mesh_notask, "the fixture shaders load as a draw loads them");
    state_reset(); g_pass.cfmt[0] = MTLPixelFormatRGBA8Unorm; g_pass.dfmt = MTLPixelFormatDepth32Float; g_pass.samples = 1;
    g_mtk.ts = ts; g_mtk.ms = ms; NvProg *prog = [NvProg new]; prog->sh[1] = fs;
    uint64_t built = g_bp_pso_n;
    require(mtk_pso(prog) != nil, "the draw builds its task / mesh pipeline");
    EXPECT("the draw's build is counted with the submit thread's pipelines", built + 1, g_bp_pso_n);
    NSString *rows = [NSString stringWithContentsOfFile:user encoding:NSUTF8StringEncoding error:nil];
    EXPECT("one M row with the task key", 1, [rows hasPrefix:@"M\t" TK "_b\t"] && [rows componentsSeparatedByString:@"\n"].count == 2);

    // The next start: the prewarm builds that row and the submit thread takes it; the draw then builds nothing
    g_pso_mtk = (nvn_hmap){.klen = sizeof(pso_key)};   // a new run's empty table (the old entries are left to leak)
    warm_load_begin(); g_warm_items = [NSMutableArray array]; atomic_store(&g_warm_ready, 0);
    long lines = 0; NSArray<WarmTask *> *tasks = warm_parse(@[user], &lines);
    EXPECT("the M row is one task / mesh warm task", 1, tasks.count == 1 && tasks[0]->kind == 3);
    if (tasks.count == 1) warm_task(tasks[0]);
    EXPECT("the prewarm built it", 1, g_warm_mps);
    warm_claim();
    EXPECT("the submit thread took it", 1, g_warm_claim_mps);
    NvShader *cts = g_shcache[@TK "_b"], *cms = g_shcache[@MK "_b"], *cfs = g_shcache[@FK "_b"];
    require(cts && cms && cfs, "the claim cached the prewarm's shaders");
    g_mtk.ts = cts; g_mtk.ms = cms; prog->sh[1] = cfs; built = g_bp_pso_n;
    EXPECT("the draw finds the prewarmed pipeline", 1, mtk_pso(prog) != nil);
    EXPECT("and builds none", built, g_bp_pso_n);

    // The task shader of a mesh shader: the nearest before it in its package file of its payload's size (not one of another size nearer, nor one after it); a recorded row's first
    NSMutableDictionary<NSString *, NvShader *> *tk = [NSMutableDictionary dictionary];
    for (NSString *k in @[@TK, @TX, @TA]) { tk[k] = mpw_load(k, 3); require(tk[k] != nil, "a task shader loads as the prewarm loads it"); }
    NvShader *pms = mpw_load(@MK, 4); require(pms && pms->mesh_payload == 4, "the mesh shader loads as the prewarm loads it");
    EXPECT("a pixel shader without a library does not load", 1, mpw_load(@FX, 1) == nil);
    g_mpw_tasks = tk; g_mpw_task_keys = @[@TK, @TX, @TA]; g_mpw_rtask = @{};
    g_mpw_pos = @{@TK: mpw_pos(@"/P.bfsha#BNSH@0x1000#var0"), @TX: mpw_pos(@"/P.bfsha#BNSH@0x2000#var0"), @TA: mpw_pos(@"/P.bfsha#BNSH@0x3000#var0"), @MK: mpw_pos(@"/P.bfsha#BNSH@0x2000#var1")};
    EXPECT("the nearest task shader before it with its payload's size", 1, mpw_task(@MK, pms) == tk[@TK]);
    g_mpw_rtask = @{@MK: @TA};
    EXPECT("a recorded row's task shader", 1, mpw_task(@MK, pms) == tk[@TA]);
    // A payload size no task shader has is a preference missed, not a reason to go without: in the package file a larger payload's nearest before it (TX, not TA nearer with a smaller
    // one); in another package file the map's first of its size, else of a larger size, else the map's first; none only with no task shader at all
    g_mpw_rtask = @{};
    NvShader *pms2 = mpw_load(@MK2, 4); require(pms2 && pms2->mesh_payload == 8, "the mesh shader with a payload size no task shader has loads");
    NSMutableDictionary *pos = [g_mpw_pos mutableCopy]; pos[@MK2] = mpw_pos(@"/P.bfsha#BNSH@0x3000#var1"); pos[@"b0b0b0b0b0b0b0b9"] = mpw_pos(@"/Q.bfsha#BNSH@0x100#var0"); g_mpw_pos = pos;
    EXPECT("no task shader of its payload's size: the nearest before it of a larger size", 1, mpw_task(@MK2, pms2) == tk[@TX]);
    NvShader *other = [NvShader new]; other->mesh_kind = 2;
    other->mesh_payload = 64; EXPECT("in another package file: the map's first of its payload's size", 1, mpw_task(@"b0b0b0b0b0b0b0b9", other) == tk[@TX]);
    other->mesh_payload = 8; EXPECT("in another package file, no task shader of its size: the map's first of a larger size", 1, mpw_task(@"b0b0b0b0b0b0b0b9", other) == tk[@TX]);
    other->mesh_payload = 256; EXPECT("in another package file, none of its size or larger: the map's first", 1, mpw_task(@"b0b0b0b0b0b0b0b9", other) == tk[@TK]);
    g_mpw_tasks = @{}; g_mpw_task_keys = @[];
    EXPECT("no task shader at all: none", 1, mpw_task(@MK, pms) == nil);
    // a mesh shader's pairs without a task shader are counted as such, not as a shader that does not load
    g_mpw_done = g_mpw_built = g_mpw_failed = g_mpw_skipped = g_mpw_notask = 0;
    MpwJob *nj = [MpwJob new]; nj->mk = @MK; nj->fk = @[@FK, @FX];
    mpw_job(nj, bp_now(), 2);
    EXPECT("a mesh shader without a task shader: both its pairs done", 2, g_mpw_done);
    EXPECT("counted as without a task shader", 2, g_mpw_notask);
    EXPECT("not as a shader that does not load", 0, g_mpw_skipped);
    EXPECT("and none built", 0, g_mpw_built);
    g_mpw_tasks = nil; g_mpw_task_keys = nil; g_mpw_pos = nil; g_mpw_rtask = nil;

    // The profile's pairs, once, in the prepare step: FK's built with MK and with MK2 (a payload size no task shader has), FX's skipped, the stamp written; the next start returns at
    // the stamp
    g_arch_dir = [g_dir stringByAppendingPathComponent:@"pso_archive"];
    NSString *stamp = [g_arch_dir stringByAppendingPathComponent:@"prebuilt_mesh.tsv"];
    mesh_prewarm(@[user], 1);
    for (int i = 0; i < 600 && ![NSFileManager.defaultManager fileExistsAtPath:stamp]; i++) usleep(50000);
    EXPECT("all three pairs done", 3, g_mpw_done);
    EXPECT("the pairs whose pixel shader has a library built, MK2's (a payload size no task shader has) among them", 2, g_mpw_built);
    EXPECT("the other skipped", 1, g_mpw_skipped);
    EXPECT("none without a task shader", 0, g_mpw_notask);
    EXPECT("none failed", 0, g_mpw_failed);
    NSString *st = [NSString stringWithContentsOfFile:stamp encoding:NSUTF8StringEncoding error:nil];
    EXPECT("the stamp names the chain, the system build and the GPU", 1, [st hasPrefix:@"chain\t" DMSH_CHAIN "\n"] && [st containsString:@"\nos\t"] && [st containsString:g_dev.name]);
    g_mpw_running = 0; int next = g_mpw_next;
    mesh_prewarm(@[user], 1);
    EXPECT("the next start returns at the stamp", next, g_mpw_next);
    EXPECT("and leaves nothing running", 0, g_mpw_running);

    [NSFileManager.defaultManager removeItemAtPath:g_dir error:nil];
    printf("t_mesh_prewarm: %d checks, %d failed\n", checks, failed);
    return failed != 0;
} }
