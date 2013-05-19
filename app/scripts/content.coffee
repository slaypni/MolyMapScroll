# require hapt_mod.js, underscore.js

settings = null

haptListen = (cb) ->
    hapt.listen( (keys, event) ->
        if not (event.target.isContentEditable or event.target.nodeName.toLowerCase() in ['textarea', 'input', 'select'])
            return cb(keys, event)
        return true
    , window, true, [])

chrome.runtime.sendMessage {type: 'getSettings'}, (_settings) ->
    settings = _settings
       
    hapt_listener = haptListen (keys) ->
        _keys = keys.join(' ')
        if _keys in (binding.join(' ') for binding in settings.bindings.toggle)
            Scroll.get().toggle()
        else if _keys in (binding.join(' ') for binding in settings.bindings.reload)
            Scroll.get().show()
            
        return true

class Scroll
    instance = null
    
    # get singleton instance
    @get: ->
        instance ?= new _Scroll()
    
    class _Scroll
        constructor: ->
            createCanvas = =>
                canvas = document.createElement('canvas')
                canvas.className = 'moly_scroll'
                canvas.width = settings.width
                canvas.height = @element.offsetHeight

                canvas.addEventListener 'mousedown', (event) =>
                    client = 
                        width: window.innerWidth or document.documentElement.clientWidth
                        height: window.innerHeight or document.documentElement.clientHeight
                    offset = -1 * @offset * (document.width / @image.width)
                    point = offset + event.clientY * (document.width / canvas.width)
                    if client.height / 2 < point < document.height - client.height / 2
                        window.scroll(window.scrollX, point - client.height / 2)
                    else if 0 <= point <= client.height / 2
                        window.scroll(window.scrollX, 0)
                    else if document.height - client.height / 2 <= point <= document.height
                        window.scroll(window.scrollX, document.height - client.height)
                
                return canvas
            
            createDragbar = =>
                dragbar = document.createElement('div')
                dragbar.id = 'dragbar'
                 
                dragbar.addEventListener 'mousedown', (event) =>
                    _callee = arguments.callee
                    dragbar.removeEventListener('mousedown', arguments.callee)
                    initial_width = parseInt(@element.style.width)
                    initial_x = event.clientX
                 
                    mousemove_handler = (event) =>
                        @width = "#{initial_x - event.clientX + initial_width}px"
                        @element.style.width = @width
                        @draw()
                    window.addEventListener('mousemove', mousemove_handler, true)
                    
                    window.addEventListener('mouseup', (event) =>
                        window.removeEventListener('mouseup', arguments.callee, true)
                        window.removeEventListener('mousemove', mousemove_handler, true)
                        dragbar.addEventListener('mousedown', _callee)
                    , true)
                     
                return dragbar

            @image = null
            @width = "#{settings.width}px"
            @element = document.createElement('div')
            @element.id = 'moly_scroll_back_panel'
            @element.style.visibility = 'hidden'
            document.querySelector('body').appendChild(@element)
            @canvas = createCanvas()
            @element.appendChild(@canvas)

            dragbar = createDragbar()
            @element.appendChild(dragbar)

            @gl = null
            @shader =
                program: null
                a: {}
                u: {}
                buffer: {}
                texture: null
            @offset = 0

            window.addEventListener 'scroll', (event) =>
                @draw()

        show: =>
            width = parseInt(@element.style.width)
            if width == 0 or isNaN(width)
                @element.style.width = @width
            @captureImage =>
                @element.style.visibility = 'visible'
                @initWebGl()
                @draw()

        toggle: =>
            width = parseInt(@element.style.width)
            if not @gl?
                if width == 0 or isNaN(width)
                    @show()
            else
                if width == 0 or isNaN(width)
                    @element.style.width = @width
                else
                    @width = @element.style.width
                    @element.style.width = "0px"

        captureImage: (cb = null) =>
            body = document.querySelector('body')
            _x = window.scrollX
            _y = window.scrollY
            html2canvas(body,
                onrendered: (canvas) =>
                    window.scrollTo(_x, _y)
                    image = new Image()
                    image.onload = =>
                        _canvas = document.createElement('canvas')
                        _canvas.height = _.min([4096, image.height])
                        _canvas.width = image.width * (_canvas.height / image.height)
                        ctx = _canvas.getContext('2d')
                        ctx.drawImage(
                            image,
                            0,
                            0,
                            image.width,
                            image.height,
                            0,
                            0,
                            _canvas.width,
                            _canvas.height
                        )
                        @image = new Image()
                        @image.onload = => cb?()
                        @image.src = _canvas.toDataURL('image/png')
                    try
                        image.src = canvas.toDataURL('image/png')
                    catch error
                        showToast = (text) =>
                            toast = document.createElement('div')
                            toast.className = 'moly_scroll_toast'
                            toast.innerText = text
                            body = document.querySelector('body')
                            body.appendChild(toast)
                            window.setTimeout( =>
                                body.removeChild(toast)
                            , 4000)
                        showToast('Failed to convert HTML into Image.')
            )

        initWebGl: =>
            return if @gl?
            
            @gl = @canvas.getContext('webgl') or @canvas.getContext('experimental-webgl')
            @gl.clearColor(0.0, 0.0, 0.0, 0.0);
            @gl.clear(@gl.COLOR_BUFFER_BIT);

            @shader.program = @gl.createProgram()

            loadShader = (code, shader_type) =>
                shader = @gl.createShader(shader_type)
                @gl.shaderSource(shader, code)
                @gl.compileShader(shader)
                is_compiled = @gl.getShaderParameter(shader, @gl.COMPILE_STATUS)
                if not is_compiled
                    console.log("#{if shader_type == @gl.VERTEX_SHADER then 'v' else 'f'}shader compile failed: #{@gl.getShaderInfoLog(shader)}")
                @gl.attachShader(@shader.program, shader)
                
            loadShader(@vertex_shader, @gl.VERTEX_SHADER)
            loadShader(@fragment_shader, @gl.FRAGMENT_SHADER)

            @gl.linkProgram(@shader.program)
            @gl.useProgram(@shader.program)

            @shader.a.position = @gl.getAttribLocation(@shader.program, 'a_position')
            @gl.enableVertexAttribArray(@shader.a.position)

            @shader.a.texture_coord = @gl.getAttribLocation(@shader.program, 'a_texture_coord')
            @gl.enableVertexAttribArray(@shader.a.texture_coord)

            @shader.buffer.whole_image_position = @gl.createBuffer()
            @shader.buffer.whole_image_texture_coord = @gl.createBuffer()

            @shader.buffer.screened_image_position = @gl.createBuffer()
            @shader.buffer.screened_image_texture_coord = @gl.createBuffer()

            @shader.u.resolution = @gl.getUniformLocation(@shader.program, 'u_resolution')
            @shader.u.canvas_aspect = @gl.getUniformLocation(@shader.program, 'u_canvas_aspect')
            @shader.u.flip_y = @gl.getUniformLocation(@shader.program, 'u_flip_y')
            @shader.u.color_filter = @gl.getUniformLocation(@shader.program, 'u_color_filter')
            @shader.u.offset = @gl.getUniformLocation(@shader.program, 'u_offset')

            uploadImage = (image) =>
                @shader.texture = @gl.createTexture()            
                @gl.bindTexture(@gl.TEXTURE_2D, @shader.texture)
                @gl.texParameteri(@gl.TEXTURE_2D, @gl.TEXTURE_WRAP_S, @gl.CLAMP_TO_EDGE)
                @gl.texParameteri(@gl.TEXTURE_2D, @gl.TEXTURE_WRAP_T, @gl.CLAMP_TO_EDGE)
                @gl.texParameteri(@gl.TEXTURE_2D, @gl.TEXTURE_MIN_FILTER, @gl.NEAREST)
                @gl.texParameteri(@gl.TEXTURE_2D, @gl.TEXTURE_MAG_FILTER, @gl.NEAREST)
                @gl.texImage2D(@gl.TEXTURE_2D, 0, @gl.RGBA, @gl.RGBA, @gl.UNSIGNED_BYTE, image)
            uploadImage(@image)

        draw: =>
            return if not @gl?
            @canvas.width = parseInt(@width)
            @canvas.height = @element.offsetHeight
            @gl.viewport(0, 0, @canvas.width, @canvas.height)
            canvas_aspect = @canvas.width / @canvas.height

            rect2coord = (rect) =>
                x1 = rect.left
                y1 = rect.top
                x2 = rect.left + rect.width
                y2 = rect.top + rect.height
                [
                    x1, y1
                    x2, y1
                    x1, y2
                    x1, y2
                    x2, y1
                    x2, y2
                ]

            uploadCoordinate = (location, buffer, coord) =>
                @gl.bindBuffer(@gl.ARRAY_BUFFER, buffer)
                @gl.bufferData(@gl.ARRAY_BUFFER, coord, @gl.STATIC_DRAW)
                @gl.vertexAttribPointer(location, 2, @gl.FLOAT, false, 0, 0)

            drawImage = (x, y, width, height, offset = [0, 0], color_filter_rgba = [1.0, 1.0, 1.0, 1.0]) =>
                uploadCoordinate(@shader.a.position, @shader.buffer.whole_image_position, new Float32Array(rect2coord({
                    left: x
                    top: y
                    width: width
                    height: height
                })))
                @gl.uniform1f(@shader.u.canvas_aspect, canvas_aspect)
                @gl.uniform2f(@shader.u.resolution, @image.width, @image.height)
                @gl.uniform1f(@shader.u.flip_y, -1)
                @gl.uniform2f(@shader.u.offset, offset[0], offset[1])
                    
                uploadCoordinate(@shader.a.texture_coord, @shader.buffer.whole_image_texture_coord, new Float32Array(rect2coord({
                    left: x
                    top: y
                    width: width
                    height: height
                })))
                rgba = color_filter_rgba
                @gl.uniform4f(@shader.u.color_filter, rgba[0], rgba[1], rgba[2], rgba[3])

                @gl.drawArrays(@gl.TRIANGLES, 0, 6)


            client = 
                width: window.innerWidth or document.documentElement.clientWidth
                height: window.innerHeight or document.documentElement.clientHeight
            window_visible_ratio =
                left: window.scrollX / document.width
                top: window.scrollY / document.height
                width: client.width / document.width
                height: client.height / document.height

            getImageOffsetTop = (y) =>
                virtual_window_image_height = @image.width / canvas_aspect
                virtual_window_height = document.width / canvas_aspect
                
                overflow_image_y = @image.height - virtual_window_image_height
                overflow_y = document.height - virtual_window_height
                if overflow_y <= 0
                    return -1 * (virtual_window_image_height - @image.height) / 2 

                scroll = window.scrollY + client.height / 2
                
                if virtual_window_height / 2 < scroll < overflow_y + (virtual_window_height / 2)
                    ((scroll - virtual_window_height / 2) / overflow_y) * overflow_image_y
                else if scroll >= overflow_y + (virtual_window_height / 2)
                    overflow_image_y
                else if scroll <= virtual_window_height / 2
                    0
            @offset = getImageOffsetTop(window.scrollY + client.height) * -1

            drawWholeImage = () =>
                drawImage(0, 0, @image.width, @image.height, [0, @offset], [0.5, 0.5, 0.5, 1.0])
                
            drawWholeImage()
            drawImage(
                window_visible_ratio.left * @image.width,
                window_visible_ratio.top * @image.height,
                window_visible_ratio.width * @image.width,
                window_visible_ratio.height * @image.height,
                [0, @offset]
            )

        vertex_shader: """
            attribute vec2 a_position;
            attribute vec2 a_texture_coord;
            
            uniform vec2 u_resolution;
            uniform float u_canvas_aspect;
            uniform float u_flip_y;
            uniform vec2 u_offset;
     
            varying vec2 v_texture_coord;

            vec2 canvas_resolution = vec2(u_resolution[0], u_resolution[0] / u_canvas_aspect);
     
            void main(){
                vec2 position = (((a_position + u_offset) * 2.0) / canvas_resolution) - 1.0;
                
                gl_Position = vec4(position * vec2(1, u_flip_y), 0, 1);
                v_texture_coord = a_texture_coord / u_resolution;
            }
        """

        fragment_shader: """
            precision mediump float;

            uniform sampler2D u_image;
            uniform vec4 u_color_filter;
         
            varying vec2 v_texture_coord;
            
            void main(){
                gl_FragColor = texture2D(u_image, v_texture_coord) * u_color_filter;
            }
        """

        
