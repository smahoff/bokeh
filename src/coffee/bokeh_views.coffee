if this.Bokeh
  Bokeh = this.Bokeh
else
  Bokeh = {}
  this.Bokeh = Bokeh
safebind = Continuum.safebind

class DeferredSVGView extends Continuum.DeferredView
  # ###class : DeferredSVGView
  # overrides make, so we create SVG elements with the appropriate namespaceURI
  # instances of this class should have some svg tagName
  tagName : 'svg'
  make: (tagName, attributes, content) ->
    el = document.createElementNS("http://www.w3.org/2000/svg", tagName)
    if (attributes)
      $(el).attr(attributes)
    if (content)
      $(el).html(content)
    return el

class PlotWidget extends DeferredSVGView
  tagName : 'g'
  initialize : (options) ->
    super(options)
    @plot_id = options.plot_id
    @plot_model = options.plot_model
    @plot_view = options.plot_view
  addPolygon: (x,y) ->
    @plot_view.ctx.fillRect(x,y,5,5)

  addCircle: (x,y) ->
    @plot_view.ctx.beginPath()

    @plot_view.ctx.arc(x, y, 5, 0, Math.PI*2)
    @plot_view.ctx.closePath()
    @plot_view.ctx.fill()
    @plot_view.ctx.stroke()
tojq = (d3selection) ->
  return $(d3selection[0][0])

# Individual Components below.
# we first define the default view for a component,
# the model for the component, and the collection

#  Plot Container


class GridPlotContainerView extends DeferredSVGView
  tagName : 'svg'
  default_options : {
    scale:1.0
  }
  initialize : (options) ->
    super(_.defaults(options, @default_options))
    @childviews = {}
    @build_children()
    @request_render()
    safebind(this, @model, 'change:children', @build_children)
    safebind(this, @model, 'change', @request_render)
    safebind(this, @model, 'destroy', () => @remove())
    @png_data_url_deferred = $.Deferred()
    return this

  to_png_daturl: () ->
    if @png_data_url_deferred.isResolved()
      return @png_data_url_deferred
    @render_deferred_components(true)
    svg_el = $(@el).find('svg')[0]
    SVGToCanvas.exportPNGcanvg(svg_el, (dataUrl) =>
      console.log(dataUrl.length, dataUrl[0..100])
      @png_data_url_deferred.resolve(dataUrl))
    return @png_data_url_deferred.promise()

  build_children : ->
    node = @build_node()
    childspecs = []
    for row in @mget('children')
      for x in row
        @model.resolve_ref(x).set('usedialog', false)
        childspecs.push(x)
    build_views(@model, @childviews, childspecs)

  build_node : ->
    d3el = d3.select(@el)
    @d3plot = d3el.append('g')
    return @d3plot

  render_deferred_components : (force) ->
    super(force)
    for row, ridx in @mget('children')
      for plotspec, cidx in row
        @childviews[plotspec.id].render_deferred_components(force)

  render : ->
    super()
    trans_string = "scale(#{@options.scale}, #{@options.scale})"
    trans_string += "translate(#{@mget('border_space')}, #{@mget('border_space')})"
    @d3plot.attr('transform', trans_string)
    d3el = d3.select(@el)
    d3el.attr('width', @options.scale * @mget('outerwidth'))
      .attr('height', @options.scale * @mget('outerheight'))
      .attr('x', @model.position_x())
      .attr('y', @model.position_y())
    row_heights =  @model.layout_heights()
    col_widths =  @model.layout_widths()
    y_coords = [0]
    _.reduceRight(row_heights[1..]
      ,
        (x, y) ->
          val = x + y
          y_coords.push(val)
          return val
      , 0
    )
    y_coords.reverse()
    x_coords = [0]
    _.reduce(col_widths[..-1]
      ,
        (x,y) ->
          val = x + y
          x_coords.push(val)
          return val
      , 0
    )
    for row, ridx in @mget('children')
      for plotspec, cidx in row
        plot = @model.resolve_ref(plotspec)
        plot.set(
          offset : [x_coords[cidx], y_coords[ridx]]
          usedialog : false
        )

    for own key, view of @childviews
      tojq(@d3plot).append(view.$el)
    @render_end()


class PlotView extends DeferredSVGView
  default_options : {
    scale:1.0
  }

  tagName : 'svg'

  initialize : (options) ->
    super(_.defaults(options, @default_options))
    @renderers = {}
    @axes = {}
    @tools = {}
    @overlays = {}


    @build_renderers()
    @build_axes()
    @build_tools()
    @build_overlays()

    @render()
    safebind(this, @model, 'change:renderers', @build_renderers)
    safebind(this, @model, 'change:axes', @build_axes)
    safebind(this, @model, 'change:tools', @build_tools)
    safebind(this, @model, 'change', @request_render)
    safebind(this, @model, 'destroy', () => @remove())

    @png_data_url_deferred = $.Deferred()
    return this

  build_renderers : ->
    build_views(@model, @renderers, @mget('renderers')
      ,
        plot_id : @id,
        plot_model : @model
        plot_view : @
    )

  build_axes : ->
    build_views(@model, @axes, @mget('axes')
      ,
        plot_id : @id
        plot_model : @model
        plot_view : @
    )

  build_tools : ->
    build_views(@model, @tools, @mget('tools')
      ,
        plot_id : @id,
        plot_model : @model
        plot_view : @
    )

  build_overlays : ->
    #add ids of renderer views into the overlay spec
    overlays = (_.clone(x) for x in @mget('overlays'))
    for overlayspec in overlays
      overlay = @model.resolve_ref(overlayspec)
      if not overlayspec['options']
        overlayspec['options'] = {}
      overlayspec['options']['rendererviews'] = []
      for renderer in overlay.get('renderers')
        overlayspec['options']['rendererviews'].push(@renderers[renderer.id])
    build_views(@model, @overlays, overlays
      ,
        plot_id : @id,
        plot_model : @model
        plot_view : @
    )

  bind_overlays : ->
    for overlayspec in @mget('overlays')
      @overlays[overlayspec.id].bind_events(this)

  bind_tools : ->
    for toolspec in   @mget('tools')
      @tools[toolspec.id].bind_events(this)

  tagName : 'svg'

  render_mainsvg : ->
    @$el.children().detach()
    d3el = d3.select(@el)
    @d3plot = d3el.append('g')
    @d3bg = @d3plot.append('g')
    @d3fg = @d3plot.append('g')
    @d3fg.append('text')
      .text(@mget('title'))
      .attr('x', 0)
      .attr('y', -15)
    innerbox = @d3bg
      .append('rect')
    @d3plotwindow = @d3fg.append('svg')
    @bind_tools()
    @bind_overlays()
    @$el.attr('x', @model.position_x())
      .attr('y', @model.position_y())
    innerbox
      .attr('fill', @mget('background_color'))
      .attr('stroke', @model.get('foreground_color'))
      .attr('width', @mget('width'))
      .attr("height",  @mget('height'))
    @d3plotwindow
      .attr('width',  @mget('width'))
      .attr('height', @mget('height'))

    @$el.attr("width", @options.scale * @mget('outerwidth'))
      .attr('height', @options.scale * @mget('outerheight'))
    #svg puts origin in the top left, we want it on the bottom left
    #
    trans_string = "scale(#{@options.scale}, #{@options.scale})"
    trans_string += "translate(#{@mget('border_space')}, #{@mget('border_space')})"
    
    @d3plot.attr('transform', trans_string)
    null

  render : () ->
    super()
    @render_mainsvg();
    @d3fg.append("foreignObject")

    jq_d = $(@d3fg[0][0])
    can_holder = jq_d.find('foreignObject')
    bord = @mget('border_space')
    sub_body = can_holder.append('''
      <body xmlns="http://www.w3.org/1999/xhtml">
        <div style="position:relative;">
          <canvas ></canvas>
        </div>
      </body>''')

    @x_can = $("<canvas height='30' width='#{@mget('width')}' />")[0]
    @x_can_ctx = @x_can.getContext('2d')
    $(@x_can).attr('style', 'border:1px solid red')
    $(document.body).append(@x_can)
    wh = (el, w, h) ->
      el.attr('width', w)
      el.attr('height', h)

    # due to bugs in positioning foreignObjects inside of svg elements
    # in webkit, the canvas must be pushed via css

    # http://stackoverflow.com/questions/8185845/svg-foreignobject-behaves-as-though-absolutely-positioned-in-webkit-browsers https://bugs.webkit.org/show_bug.cgi?id=71819 http://code.google.com/p/chromium/issues/detail?id=116566 https://bugs.webkit.org/show_bug.cgi?id=48745

    @canvas = can_holder.find('canvas')
    @ctx = @canvas[0].getContext('2d')
    if navigator.userAgent.indexOf("WebKit") != -1
      @canvas.attr('style', "position:absolute; left:#{bord}px; top:#{bord}px;")
      #@canvas.attr('style', "position:absolute; left:#{bord}px; top:#{bord}px;")
      #@ctx.scale(@options.scale, @options.scale)
      @ctx.scale(0.5, 0.5)
    wh(@canvas, @mget('width'), @mget('height'))
    wh(can_holder, @mget('width'), @mget('height'))




    for own key, view of @axes
      tojq(@d3bg).append(view.$el)
    for own key, view of @renderers
      tojq(@d3plotwindow).append(view.$el)
    @render_end()
    
  render_deferred_components: (force) ->
    super(force)


    all_views = _.flatten(_.map([@tools, @axes, @renderers, @overlays], _.values))

    window.av = all_views
    if _.any(all_views, (v) -> v._dirty)
      @ctx.clearRect(0,0,  @mget('width'), @mget('height'))      
      for v in all_views
        v._dirty = true
        v.render_deferred_components(true)

build_views = Continuum.build_views

# D3LinearAxisView



class XYRendererView extends PlotWidget
  initialize : (options) ->
    safebind(this, @model, 'change', @request_render)
    safebind(this, @mget_ref('xmapper'), 'change', @request_render)
    safebind(this, @mget_ref('ymapper'), 'change', @request_render)
    safebind(this, @mget_ref('data_source'), 'change:data', @request_render)
    super(options)


  calc_buffer : (data) ->
    "use strict";
    xmapper = @model.get_ref('xmapper')
    ymapper = @model.get_ref('ymapper')
    xfield = @model.get('xfield')
    yfield = @model.get('yfield')
    datax = (x[xfield] for x in data)
    screenx = xmapper.v_map_screen(datax)
    screenx = @model.v_xpos(screenx)
    datay = (y[yfield] for y in data)
    screeny = ymapper.v_map_screen(datay)
    screeny = @model.v_ypos(screeny)
    #fix me figure out how to feature test for this so it doesn't use
    #typed arrays for browsers that don't support that

    @screeny = new Float32Array(screeny)
    @screenx = new Float32Array(screenx)
    #@screenx = screenx
    #@screeny = screeny

class D3LinearAxisView extends PlotWidget
  initialize : (options) ->
    super(options)
    @plotview = options.plotview
    safebind(this, @plot_model, 'change', @request_render)
    safebind(this, @model, 'change', @request_render)
    safebind(this, @mget_ref('mapper'), 'change', @request_render)

  tagName : 'g'

  get_offsets : (orientation) ->
    offsets =
      x : 0
      y : 0
    if orientation == 'bottom'
      offsets['y'] += @plot_model.get('height')
    return offsets

  get_tick_size : (orientation) ->
    if (not _.isNull(@mget('tickSize')))
      return @mget('tickSize')
    else
      if orientation == 'bottom'
        return -@plot_model.get('height')
      else
        return -@plot_model.get('width')

  convert_scale : (scale) ->
    domain = scale.domain()
    range = scale.range()
    if @mget('orientation') in ['bottom', 'top']
      func = 'xpos'
    else
      func = 'ypos'
    range = [@plot_model[func](range[0]), @plot_model[func](range[1])]
    scale = d3.scale.linear().domain(domain).range(range)
    return scale


  render : ->
    super()
    if not  @mget('orientation') in ['bottom', 'top']
      @render_end()
      return
    xmapper = @mget_ref('mapper')
  
    data_range = xmapper.get_ref('data_range')
    interval = ticks.auto_interval(
      data_range.get('start'), data_range.get('end'))

    [first_tick, last_tick] = ticks.auto_bounds(
      data_range.get('start'), data_range.get('end'), interval)



    
    current_tick = first_tick
    x_ticks = []
    while current_tick <= last_tick
      x_ticks.push(current_tick)
      
      current_tick += interval

    
    screenxs = xmapper.v_map_screen(x_ticks)
    screenxs = @model.v_xpos(screenxs)

    for screen_x in screenxs
      @plot_view.x_can_ctx.moveTo(screen_x, 0)
      @plot_view.x_can_ctx.lineTo(screen_x, 30)
    @plot_view.x_can_ctx.stroke()
    

    @render_end()

  render_old : ->
    super()

    window.axisview = @
    node = d3.select(@el)
    node
      .attr('style', '  font: 12px sans-serif; fill:none; stroke-width:1.5px; shape-rendering:crispEdges')
      .attr('stroke', @mget('foreground_color'))
    offsets = @get_offsets(@mget('orientation'))
    offsets['h'] = @plot_model.get('height')
    node.attr('transform', "translate(#{offsets.x}, #{offsets.y})")
    
    axis = d3.svg.axis()
    ticksize = @get_tick_size(@mget('orientation'))
    scale_converted = @convert_scale(@mget_ref('mapper').get('scale'))
    temp = axis.scale(scale_converted)
    temp.orient(@mget('orientation'))
      .ticks(@mget('ticks'))
      .tickSubdivide(@mget('tickSubdivide'))
      .tickSize(ticksize)
      .tickPadding(@mget('tickPadding'))
    node.call(axis)
    node.selectAll('.tick').attr('stroke', @mget('tick_color'))
    @render_end()

class D3LinearDateAxisView extends D3LinearAxisView
  convert_scale : (scale) ->
    domain = scale.domain()
    range = scale.range()
    if @mget('orientation') in ['bottom', 'top']
      func = 'xpos'
    else
      func = 'ypos'
    range = [@plot_model[func](range[0]), @plot_model[func](range[1])]
    domain = [new Date(domain[0]), new Date(domain[1])]
    scale = d3.time.scale().domain(domain).range(range)
    return scale


class BarRendererView extends XYRendererView
  render_bars : (orientation) ->
    if orientation == 'vertical'
      index_mapper = @mget_ref('xmapper')
      value_mapper = @mget_ref('ymapper')
      value_field = @mget('yfield')
      index_field = @mget('xfield')
      index_coord = 'x'
      value_coord = 'y'
      index_dimension = 'width'
      value_dimension = 'height'
      indexpos = (x, width) =>
        @model.position_object_x(x, @mget('width'), width)
      valuepos = (y, height) =>
        @model.position_object_y(y, @mget('height'), height)
    else
      index_mapper = @mget_ref('ymapper')
      value_mapper = @mget_ref('xmapper')
      value_field = @mget('xfield')
      index_field = @mget('yfield')
      index_coord = 'y'
      value_coord = 'x'
      index_dimension = 'height'
      value_dimension = 'width'
      valuepos = (x, width) =>
        @model.position_object_x(x, @mget('width'), width)
      indexpos = (y, height) =>
        @model.position_object_y(y, @mget('height'), height)

    if not _.isObject(index_field)
      index_field = {'field' : index_field}
    data_source = @mget_ref('data_source')

    if _.has(index_field, index_dimension)
      thickness = index_field[index_dimension]
    else
      thickness = 0.85 * @plot_model.get(index_dimension)
      thickness = thickness / data_source.get('data').length

    left_points = []
    data_arr = @model.get_ref('data_source').get('data')
    for d, idx in data_arr
      ctr = index_mapper.map_screen(d[index_field['field']])
      left_points[idx] = indexpos(ctr - thickness / 2.0, thickness)

    height_base = value_mapper.map_screen(0)
    heights = []

    for d, idx in data_arr
      heights[idx] = value_mapper.map_screen(d[value_field])



    if orientation == "vertical"
      value_pos = (y) =>
        vp =  (@mget('height') - y)
        return vp
      for i in [0..heights.length]
        @plot_view.ctx.fillRect(left_points[i], value_pos(heights[i]), thickness, value_pos(0))
    else
      value_pos = (x) =>
        vp =  (@mget('width') - x)
        return vp
    
      for i in [0..heights.length]
        @plot_view.ctx.fillRect(0, left_points[i], value_pos(heights[i]), thickness)
    
    @plot_view.ctx.stroke()
    return null


  render : () ->
    super()
    @render_bars(@mget('orientation'))
    @render_end()
    return null


class LineRendererView extends XYRendererView

  render : ->
    super()
    
    data = @model.get_ref('data_source').get('data')
    @calc_buffer(data)

    @plot_view.ctx.fillStyle = 'blue'
    @plot_view.ctx.strokeStyle = @mget('color')
    @plot_view.ctx.beginPath()
    if navigator.userAgent.indexOf("WebKit") != -1
      @ctx.scale(0.5, 0.5)

    @plot_view.ctx.moveTo(@screenx[0], @screeny[0])
    for idx in [1..@screenx.length]
      @plot_view.ctx.lineTo(@screenx[idx], @screeny[idx])
    @plot_view.ctx.stroke()
    @render_end()

    return null

class ScatterRendererView extends XYRendererView
  render : ->
    "use strict";
    super()
    if @model.get_ref('data_source').get('selecting') == true
        #skip data sources which are not selecting'
        @render_end()
        return null
    
    data = @model.get_ref('data_source').get('data')
    a = new Date()
    @calc_buffer(data)
    @plot_view.ctx.beginPath()
    #if navigator.userAgent.indexOf("WebKit") != -1
      #@ctx.scale(0.5, 0.5)
    if navigator.userAgent.indexOf("WebKit") != -1
      @plot_view.ctx.scale(@options.scale, @options.scale)

    @plot_view.ctx.fillStyle = @mget('foreground_color')
    @plot_view.ctx.strokeStyle = @mget('foreground_color')
    color_field = @mget('color_field')
    ctx = @plot_view.ctx
    m2pi = Math.PI*2
    if color_field
      color_mapper = @model.get_ref('color_mapper')
      color_arr = @model.get('color_field')
    mark_type = @mget('mark')
    for idx in [0..@screeny.length]
      if color_field
        comp_color = color_mapper.map_screen(idx)
        @plot_view.ctx.strokeStyle = comp_color
        @plot_view.ctx.fillStyle = comp_color
      if mark_type == "square"
        @addPolygon(@screenx[idx], @screeny[idx])
      else
        @addCircle(@screenx[idx], @screeny[idx])

    @plot_view.ctx.stroke()
    @render_end()
    b = new Date()
    render_time = b-a
    $('#timer').html( "render time #{render_time}")
    return null


#  tools

class PanToolView extends PlotWidget
  initialize : (options) ->
    @dragging = false
    super(options)

  mouse_coords : () ->
    plot = @plot_view.d3plotwindow
    [x, y] = d3.mouse(plot[0][0])
    [x, y] = [@plot_model.rxpos(x), @plot_model.rypos(y)]
    return [x, y]

  _start_drag : () ->
    @dragging = true
    [@x, @y] = @mouse_coords()
    xmappers = (@model.resolve_ref(x) for x in @mget('xmappers'))
    ymappers = (@model.resolve_ref(x) for x in @mget('ymappers'))

  _drag_mapper : (mapper, diff) ->
    screen_range = mapper.get_ref('screen_range')
    data_range = mapper.get_ref('data_range')
    screenlow = screen_range.get('start') - diff
    screenhigh = screen_range.get('end') - diff
    [start, end] = [mapper.map_data(screenlow), mapper.map_data(screenhigh)]
    data_range.set({
      'start' : start
      'end' : end
    }, {'local' : true})

  _drag : (xdiff, ydiff) ->
    plot = @plot_view.d3plotwindow
    if _.isUndefined(xdiff) or _.isUndefined(ydiff)
      [x, y] = @mouse_coords()
      xdiff = x - @x
      ydiff = y - @y
      [@x, @y] = [x, y]
    xmappers = (@model.resolve_ref(x) for x in @mget('xmappers'))
    ymappers = (@model.resolve_ref(x) for x in @mget('ymappers'))
    for xmap in xmappers
      @_drag_mapper(xmap, xdiff)
    for ymap in ymappers
      @_drag_mapper(ymap, ydiff)

  bind_events : (plotview) ->
    @plotview = plotview
    node = d3.select(@plot_view.el)
    node.attr('pointer-events' , 'all')
    node.on("mousemove.drag"
      ,
        () =>
          if d3.event.shiftKey
            if not @dragging
              @_start_drag()
            else
              @_drag()
            d3.event.preventDefault()
            d3.event.stopPropagation()
          else
            @dragging = false
          return null
    )

class SelectionToolView extends PlotWidget
  initialize : (options) ->
    super(options)
    @selecting = false
    select_callback = _.debounce((() => @_select_data()),50)
    safebind(this, @model, 'change', @request_render)
    safebind(this, @model, 'change', select_callback)
    for renderer in @mget('renderers')
      renderer = @model.resolve_ref(renderer)
      safebind(this, renderer, 'change', @request_render)
      safebind(this, renderer.get_ref('xmapper'), 'change', @request_render)
      safebind(this, renderer.get_ref('ymapper'), 'change', @request_render)
      safebind(this, renderer.get_ref('data_source'), 'change', @request_render)
      safebind(this, renderer, 'change', select_callback)
      safebind(this, renderer.get_ref('xmapper'), 'change', select_callback)
      safebind(this, renderer.get_ref('ymapper'), 'change', select_callback)


  bind_events : (plotview) ->
    @plotview = plotview
    node = d3.select(@plot_view.el)
    node.attr('pointer-events' , 'all')
    node.on("mousedown.selection"
      ,
        () =>
          @_stop_selecting()
    )
    node.on("mousemove.selection"
      ,
        () =>
          if d3.event.ctrlKey
            if not @selecting
              @_start_selecting()
            else
              @_selecting()
            d3.event.preventDefault()
            d3.event.stopPropagation()
          return null
    )

  mouse_coords : () ->
    plot = @plot_view.d3plotwindow
    [x, y] = d3.mouse(plot[0][0])
    [x, y] = [@plot_model.rxpos(x), @plot_model.rypos(y)]
    return [x, y]

  _stop_selecting : () ->
    @mset(
      start_x : null
      start_y : null
      current_x : null
      current_y : null
    )
    for renderer in @mget('renderers')
      @model.resolve_ref(renderer).get_ref('data_source').set('selecting', false)
      @model.resolve_ref(renderer).get_ref('data_source').save()
    @selecting = false
    if @shading
      @shading.remove()
      @shading = null

  _start_selecting : () ->
    [x, y] = @mouse_coords()
    @mset({'start_x' : x, 'start_y' : y, 'current_x' : null, 'current_y' : null})
    for renderer in @mget('renderers')
      data_source = @model.resolve_ref(renderer).get_ref('data_source')
      data_source.set('selecting', true)
      data_source.save()
    @selecting = true

  _get_selection_range : ->
    xrange = [@mget('start_x'), @mget('current_x')]
    yrange = [@mget('start_y'), @mget('current_y')]
    if @mget('select_x')
      xrange = [d3.min(xrange), d3.max(xrange)]
    else
      xrange = null
    if @mget('select_y')
      yrange = [d3.min(yrange), d3.max(yrange)]
    else
      yrange = null
    return [xrange, yrange]

  _selecting : () ->
    [x, y] = @mouse_coords()
    @mset({'current_x' : x, 'current_y' : y})
    return null

  _select_data : () ->
    if not @selecting
      return
    [xrange, yrange] = @_get_selection_range()
    datasources = {}
    datasource_selections = {}

    for renderer in @mget('renderers')
      datasource = @model.resolve_ref(renderer).get_ref('data_source')
      datasources[datasource.id] = datasource

    for renderer in @mget('renderers')
      datasource_id = @model.resolve_ref(renderer).get_ref('data_source').id
      _.setdefault(datasource_selections, datasource_id, [])
      selected = @model.resolve_ref(renderer).select(xrange, yrange)
      datasource_selections[datasource.id].push(selected)

    for own k,v of datasource_selections
      selected = _.intersect.apply(_, v)
      datasources[k].set('selected', selected)
      datasources[k].save()
    return null

  _render_shading : () ->
    [xrange, yrange] = @_get_selection_range()
    if _.any(_.map(xrange, _.isNullOrUndefined)) or
      _.any(_.map(yrange, _.isNullOrUndefined))
        return
    if not @shading
      @shading = @plot_view.d3plotwindow.append('rect')
    if xrange
      width = xrange[1] - xrange[0]
      @shading.attr('x', @plot_model.position_child_x(width, xrange[0]))
        .attr('width', width)
    else
      width = @plot_model.get('width')
      @shading.attr('x',  @plot_model.position_child_x(xrange[0]))
        .attr('width', width)
    if yrange
      height = yrange[1] - yrange[0]
      @shading.attr('y', @plot_model.position_child_y(height, yrange[0]))
        .attr('height', height)
    else
      height = @plot_model.get('height')
      @shading.attr('y', @plot_model.position_child_y(height, yrange[0]))
        .attr('height', height)
    @shading.attr('fill', '#000').attr('fill-opacity', 0.1)

  render : () ->
    super()
    @_render_shading()
    @render_end()
    return null

class OverlayView extends PlotWidget
  initialize : (options) ->
    @rendererviews = options['rendererviews']
    super(options)

  bind_events : (plotview) ->
    @plotview = plotview
    return null

window.sel_debug = false
class ScatterSelectionOverlayView extends OverlayView
  initialize : (options) ->
    super(options)
    for renderer in @mget('renderers')
      renderer = @model.resolve_ref(renderer)
      safebind(this, renderer, 'change', @request_render)
      safebind(this, renderer.get_ref('xmapper'), 'change', @request_render)
      safebind(this, renderer.get_ref('ymapper'), 'change', @request_render)
      safebind(this, renderer.get_ref('data_source'), 'change', @request_render)

  render : () ->
    window.overlay_render += 1
    super()
    for temp in _.zip(@mget('renderers'), @rendererviews)
      if window.sel_debug
        debugger;
      [renderer, rendererview] = temp
      renderer = @model.resolve_ref(renderer)
      selected = {}
      if renderer.get_ref('data_source').get('selecting') == false
        #skip data sources which are not selecting'
        continue
      sel_idxs = renderer.get_ref('data_source').get('selected')
      ds = renderer.get_ref('data_source')
      data = ds.get('data')
      fcolor = @mget('foreground_color')
      rvm = rendererview.model
      
      fcolor = rvm.get('foreground_color')
      unselected_color = @mget('unselected_color')
      color_field = rvm.get('color_field')
      if color_field
        color_mapper = rvm.get_ref('color_mapper')
      color_arr = rvm.get('color_field')
      mark_type = @mget('mark')
      last_color_field = fcolor
      @plot_view.ctx.strokeStyle = fcolor
      @plot_view.ctx.fillStyle = fcolor
      
      last_color_field = false
      ctx = @plotview.ctx
      for idx in [0..data.length]
        
        if idx in sel_idxs
          if color_field
            comp_color = color_mapper.map_screen(idx)
            ctx.strokeStyle = comp_color
            ctx.fillStyle = comp_color
          else
            ctx.strokeStyle = fcolor
            ctx.fillStyle = fcolor
            
        else
          ctx.fillStyle = unselected_color
          ctx.strokeStyle = unselected_color
        if mark_type == "square"
          @addPolygon(rendererview.screenx[idx], rendererview.screeny[idx])
        else
          @addCircle(rendererview.screenx[idx], rendererview.screeny[idx])
    @plot_view.ctx.stroke()
    @render_end()
    return null


window.overlay_render = 0
class ZoomToolView extends PlotWidget
  initialize : (options) ->
    super(options)

  mouse_coords : () ->
    plot = @plot_view.d3plotwindow
    [x, y] = d3.mouse(plot[0][0])
    [x, y] = [@plot_model.rxpos(x), @plot_model.rypos(y)]
    return [x, y]

  _zoom_mapper : (mapper, eventpos, factor) ->
    screen_range = mapper.get_ref('screen_range')
    data_range = mapper.get_ref('data_range')
    screenlow = screen_range.get('start')
    screenhigh = screen_range.get('end')
    start = screenlow - (eventpos - screenlow) * factor
    end = screenhigh + (screenhigh - eventpos) * factor
    [start, end] = [mapper.map_data(start), mapper.map_data(end)]
    data_range.set({
      'start' : start
      'end' : end
    }, {'local' : true})

  _zoom : () ->
    [x, y] = @mouse_coords()
    factor = - @mget('speed') * d3.event.wheelDelta
    xmappers = (@model.resolve_ref(mapper) for mapper in @mget('xmappers'))
    ymappers = (@model.resolve_ref(mapper) for mapper in @mget('ymappers'))
    for xmap in xmappers
      @_zoom_mapper(xmap, x, factor)
    for ymap in ymappers
      @_zoom_mapper(ymap, y, factor)

  bind_events : (plotview) ->
    @plotview = plotview
    node = d3.select(@plot_view.el)
    node.attr('pointer-events' , 'all')
    node.on("mousewheel.zoom"
      ,
        () =>
          @_zoom()
          d3.event.preventDefault()
          d3.event.stopPropagation()
    )

Bokeh.PlotWidget = PlotWidget
Bokeh.PlotView = PlotView
Bokeh.ScatterRendererView = ScatterRendererView
Bokeh.LineRendererView = LineRendererView
Bokeh.BarRendererView = BarRendererView
Bokeh.GridPlotContainerView = GridPlotContainerView
Bokeh.PanToolView = PanToolView
Bokeh.ZoomToolView = ZoomToolView
Bokeh.SelectionToolView = SelectionToolView
Bokeh.ScatterSelectionOverlayView = ScatterSelectionOverlayView
Bokeh.D3LinearAxisView = D3LinearAxisView
Bokeh.D3LinearDateAxisView = D3LinearDateAxisView
