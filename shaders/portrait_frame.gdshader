shader_type canvas_item;
render_mode blend_mix;
// ============================================================================
//  《涌现》立绘合成 —— 让"白底灰白手绘立绘"长进"暗调手绘场景"里
// ============================================================================
//  立绘是灰白手绘、纸是白的、背景也是白的，直接贴到暗色场景上会是一块刺眼的
//  白色矩形。所以这里要做的是"只抠掉人物外轮廓之外的白纸"。
//
//  【为什么需要 bg_mask 这张贴图】（这是本文件最重要的一段，改之前先读完）
//    最早的做法是"按亮度一刀切"：亮度接近白纸的像素统统挖成透明。
//    这对**人物内部**的白色是灾难——
//      · 眼镜片的反光、衬衫的受光面、脸的高光，亮度都能到 0.90~1.00
//      · 于是它们被当成"纸"一起挖掉了，人物身上破出一个个洞，整张脸会消失
//    正确语义是"只抠外轮廓之外的纸"——**与画面四边连通、或者面积很小的**那些区域，
//    而人物本体（被线稿围住的大块不透明区）必须原样保留。
//    注意：判据是**连通性 / 面积，不是亮度**。这两张立绘的白色连帽衫和整张脸
//    亮度就是 1.0，跟纸一模一样，任何"亮度阈值"都会把人物一起吃掉。
//    canvas_item 的 shader 里没法高效地做连通性判断，所以在 CPU 侧
//    （scripts/ui/prelude_ui.gd 的 build_bg_mask）先做一次连通性判断，
//    把结果烘成一张灰度贴图塞进 bg_mask：
//      R 通道 = 1 → 这个像素属于背景（透明区 / 小残渣），可以被抠
//      R 通道 = 0 → 人物本体，一律保留（含白衬衫、脸、眼镜反光）
//
//  两个已经踩过的 shader 坑（改这个文件前先读）：
//   a) 不要写带 sampler2D 参数的辅助函数。Godot 会报
//        ERROR: Condition "!actions.custom_samplers.has(...)" is true.
//      原因是 canvas_item 的 TEXTURE 是内建 sampler，传进自定义函数后编译器的
//      sampler 表对不上。取样一律写在 fragment() 里。
//   b) TEXTURE / TEXTURE_PIXEL_SIZE 只在 fragment() 作用域可见，写在普通函数里会报
//        SHADER ERROR: Unknown identifier in expression: 'TEXTURE'.
// ============================================================================

// 外轮廓之外的白纸从哪个亮度开始被吃掉（软过渡的起点）
uniform float paper_from : hint_range(0.6, 1.0) = 0.88;
// 纸张剔除的软过渡宽度（越接近 paper_from，过渡越窄越硬）
uniform float paper_soft : hint_range(0.0, 0.2) = 0.10;
// 背景遮罩（由 build_bg_mask() 烘出来）：R=1 表示"背景，可以抠"
uniform sampler2D bg_mask : hint_default_white, filter_nearest;
// 边缘溶解强度
uniform float dissolve : hint_range(0.0, 1.0) = 0.55;
// 溶解从哪个比例开始（0.5 = 从正中间就开始化）
uniform float dissolve_inner : hint_range(0.0, 0.5) = 0.30;
// 边光强度（暖色描边，用于暗背景）
uniform float rim : hint_range(0.0, 1.0) = 0.34;
uniform vec4 rim_color : source_color = vec4(1.0, 0.88, 0.68, 1.0);
// 暗描边强度（用于浅背景，防止人物糊在亮处）
uniform float outline : hint_range(0.0, 1.0) = 0.18;
uniform vec4 outline_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);
// 变暗（0 = 原色，1 = 很暗）—— 让非说话人退到后景
uniform float dim : hint_range(0.0, 1.0) = 0.0;
// 聚焦（1 = 正在说话的人）：这一位不吃边缘溶解，也不会被背景遮罩的软过渡削掉alpha，
// 换句话说"正在说话的那个人永远是实心的"
uniform float focus : hint_range(0.0, 1.0) = 0.0;
// 整体色调
uniform vec3 tint : source_color = vec3(0.99, 0.98, 0.96);

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, LUMA);

	// ---- 1. 纸张剔除：只抠 bg_mask 标出来的背景
	//
	// 【重要】这两张立绘本来就带 alpha（四角 a=0），背景是透明而不是白纸。
	// 所以这里以 bg_mask（由 build_bg_mask() 按连通性/面积烘出来）为准：
	//   背景区（透明 / 小残渣）→ 清掉，再对残留的浅色做一点软过渡，边缘不锯齿
	//   人物本体                → **原样保留 alpha**，绝不按亮度再削一刀
	// 千万不要改回"按亮度一刀切"：那会把衬衫受光面、脸、眼镜反光一起抠掉。
	float mask = texture(bg_mask, UV).r;
	float a;
	if (mask > 0.5) {
		// focus（正在说话的人）不吃这段软过渡：他要的是"实心"
		a = c.a * (1.0 - smoothstep(0.45, 0.90, l) * (1.0 - focus * 0.45));
	} else {
		a = c.a;
	}

	// ---- 2. 四周边缘溶解（切比雪夫距离，贴合矩形）
	vec2 p = abs(UV - vec2(0.5)) * 2.0;
	float d = max(p.x, p.y);
	float border = smoothstep(1.0, dissolve_inner, d);
	// 正在说话的人几乎不溶解（dissolve 的 30%），保证他是画面里最实的那一个
	a *= mix(1.0, border, dissolve * mix(1.0, 0.30, focus));

	// ---- 3. 轮廓：只看"已经不是纸"的区域
	float edge = clamp(a * 2.0, 0.0, 1.0);

	// 亮度梯度 → 线稿边缘。取样必须写在 fragment() 里（见文件头坑 a/b）。
	float lx = dot(texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).rgb, LUMA);
	float ly = dot(texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).rgb, LUMA);
	float g = clamp((abs(l - lx) + abs(l - ly)) * 7.0, 0.0, 1.0);

	vec3 rgb = c.rgb * tint;

	// 暗描边：压住浅色区域，让线稿更清楚
	rgb = mix(rgb, outline_color.rgb, g * outline * edge);
	// 暖边光：暗背景里的分离度
	rgb += rim_color.rgb * g * rim * edge * (1.0 - dim * 0.6);

	// ---- 4. 后景变暗
	rgb = mix(rgb, vec3(0.02, 0.02, 0.03), dim * 0.62);
	// 正在说话的人再提一点点亮度和对比，跟旁边的听众拉开
	rgb = mix(rgb, clamp(rgb * 1.06 + vec3(0.008), vec3(0.0), vec3(1.0)), focus);

	COLOR = vec4(rgb, a);
}
