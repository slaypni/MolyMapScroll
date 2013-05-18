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
        if _keys in (binding.join(' ') for binding in settings.bindings.show)
            Scroll.get().show()
            
        return true

window.addEventListener 'scroll', (event) ->
    Scroll.get().set()

class Scroll
    instance = null
    
    # get singleton instance
    @get: ->
        instance ?= new _Scroll()
    
    class _Scroll
        constructor: ->
            @image = null
            @element = document.createElement('div')
            @element.id = 'moly_scroll_back_panel'
            @element.style.visibility = 'hidden'
            document.querySelector('body').appendChild(@element)
            @canvas = document.createElement('canvas')
            @canvas.className = 'moly_scroll'
            @canvas.width = @element.offsetWidth
            @canvas.height = @element.offsetHeight
            @element.appendChild(@canvas)

        show: =>
            @captureImage =>
                @set()
                @element.style.visibility = 'visible'

        captureImage: (cb = null) =>
            body = document.querySelector('body')
            _x = window.scrollX
            _y = window.scrollY
            html2canvas(body,
                onrendered: (canvas) =>
                    window.scrollTo(_x, _y)
                    @image = new Image()
                    @image.onload = => cb?()
                    @image.src = canvas.toDataURL('image/png')
            )

        set: =>
            client = 
                width: window.innerWidth or document.documentElement.clientWidth
                height: window.innerHeight or document.documentElement.clientHeight
            window_visible_ratio =
                left: window.scrollX / document.width
                top: window.scrollY / document.height
                width: client.width / document.width
                height: client.height / document.height

            getScreenedImage = (cb) =>
                _canvas = document.createElement('canvas')
                _canvas.width = @image.width
                _canvas.height = @image.height
                ctx = _canvas.getContext('2d');
                
                ctx.drawImage(@image, 0, 0)
                
                ctx.globalAlpha = 0.5
                ctx.fillStyle = "rgba(0, 0, 0)"
                ctx.fillRect(0, 0, @image.width, @image.height)
     
                ctx.globalAlpha = 1.0
                ctx.drawImage(
                    @image,
                    window_visible_ratio.left * @image.width,
                    window_visible_ratio.top * @image.height,
                    window_visible_ratio.width * @image.width,
                    window_visible_ratio.height * @image.height,
                    window_visible_ratio.left * @image.width,
                    window_visible_ratio.top * @image.height,
                    window_visible_ratio.width * @image.width,
                    window_visible_ratio.height * @image.height
                )
     
                image = new Image()
                image.onload = => cb?(image)
                image.src = _canvas.toDataURL('image/png')
                return image

            getScreenedImage (image) =>

                canvas_aspect = @canvas.offsetWidth / @canvas.offsetHeight
                
                getImageOffsetTop = (y) =>
                    overflow_image_y = image.height - (image.width / canvas_aspect)
                    overflow_y = document.height - (document.width / canvas_aspect)
                    return 0 if overflow_y <= 0
                    
                    _y = y - (document.height / 2)
                    if 0 < _y < overflow_y
                        (_y / overflow_y) * overflow_image_y
                    else if _y >= overflow_y
                        overflow_y
                    else if _y <= 0
                        0
     
                ctx = @canvas.getContext('2d');
                ctx.drawImage(
                    image,
                    0,
                    getImageOffsetTop(window.scrollY + client.height),
                    image.width,
                    Math.floor(_.min([image.height, image.width / canvas_aspect])),
                    0,
                    _.max([0, ((1 / canvas_aspect) - (image.height / image.width)) * (@canvas.width / 2)]),
                    @canvas.width,
                    _.min([@canvas.height, (image.height / image.width) * @canvas.width])
                )
                    

