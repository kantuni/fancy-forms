module Form exposing (..)

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode as D exposing (Decoder)
import Json.Encode as E exposing (Value)
import Maybe exposing (withDefault)
import String exposing (fromInt, toInt)


type Msg
    = FormMsg FieldId Value

render : (Msg -> msg) -> Form a customError -> FormState -> Html msg
render toMsg f formState =
    let
        errors =
            let
                ( data, validator ) =
                    f.fn.combine formState
            in
            validator data
    in
    
    f.fn.view formState errors
        |> Html.map toMsg  


updateField : FormInternal a customError -> FieldId -> Value -> FormState -> FormState
updateField { updates } fieldId msgValue ((FormState formState) as fs) =
    let
        updateFn =
            Dict.get fieldId updates
                |> withDefault (\_ modelValue_ -> modelValue_)

        modelValue =
            read fieldId fs

        updatedModelValue =
            updateFn msgValue modelValue
    in
    FormState { formState | values = Dict.insert fieldId updatedModelValue formState.values }


type alias FieldId =
    Int


type FormState
    = FormState
        { parentDomId : DomId
        , values : Dict FieldId Value
        }


type alias Field a customError =
    { id : FieldId
    , value : FormState -> a
    , errors : FormState -> List (Error customError)
    , view : FormState -> Html Msg
    }


mkField : (List (Error customError) -> Html Msg -> Html Msg) -> FieldId -> Widget model msg value customError -> Field value customError
mkField fieldWithErrors fieldId widget =
    let
        deserializeModel : FormState -> model
        deserializeModel formState =
            D.decodeValue widget.decoderModel (read fieldId formState)
                |> Result.toMaybe
                |> withDefault widget.init

        viewField : FormState -> Html Msg
        viewField ((FormState { parentDomId }) as formState) =
            let
                toMsg : msg -> Msg
                toMsg msg =
                    FormMsg fieldId <|
                        widget.encodeMsg msg

                fieldErrors =
                    errors_ formState

                inputHtml =
                    deserializeModel formState
                        |> widget.view (parentDomId ++ "f-" ++ fromInt fieldId)
                        |> Html.map toMsg
            in
            fieldWithErrors fieldErrors inputHtml

        value : FormState -> value
        value formState =
            deserializeModel formState
                |> widget.value

        errors_ : FormState -> List (Error customError)
        errors_ formState =
            deserializeModel formState
                |> widget.validate
    in
    { id = fieldId
    , value = value
    , errors = errors_
    , view = viewField
    }


read : FieldId -> FormState -> Value
read fieldId (FormState { values }) =
    Dict.get fieldId values
        |> withDefault (E.object [])


type alias Form data customError =
    FormInternal
        { view : FormState -> List (Error customError) -> Html Msg
        , combine : FormState -> ( data, Validator data customError )
        }
        customError


init : FormState
init =
    FormState
        { parentDomId = ""
        , values = Dict.empty
        }


type alias FormInternal f customError =
    { fn : f
    , count : Int
    , updates : Dict FieldId (Value -> Value -> Value)
    , fieldWithErrors : List (Error customError) -> Html Msg -> Html Msg
    }


form : (List (Error customError) -> Html Msg -> Html Msg) -> a -> FormInternal a customError
form fieldWithErrors fn =
    { fn = fn
    , count = 0
    , updates = Dict.empty
    , fieldWithErrors = fieldWithErrors
    }


field : Widget widgetModel msg value customError -> FormInternal (Field value customError -> c) customError -> FormInternal c customError
field widget { fn, count, updates, fieldWithErrors } =
    { fn = fn (mkField fieldWithErrors count widget)
    , count = count + 1
    , updates =
        Dict.insert
            count
            (encodedUpdate widget)
            updates
    , fieldWithErrors = fieldWithErrors
    }


wrap :
    Widget widgetModel msg value customError
    -> (DomId -> Html msg -> Html msg)
    -> Widget widgetModel msg value customError
wrap widget container =
    { widget
        | view = \domId model -> container domId <| widget.view domId model
    }


encodedUpdate :
    Widget model msg value customError
    -> Value
    -> Value
    -> Value
encodedUpdate ({ decoderMsg, decoderModel, encodeModel } as widget) msgVal modelVal =
    case ( D.decodeValue decoderMsg msgVal, D.decodeValue decoderModel modelVal ) of
        ( Ok msg, Ok model ) ->
            widget.update msg model |> encodeModel

        ( Ok msg, _ ) ->
            widget.update msg widget.init |> encodeModel

        _ ->
            modelVal


type alias DomId =
    String


type alias Widget model msg value customError =
    { init : model
    , value : model -> value
    , validate : Validator model customError
    , view : DomId -> model -> Html msg
    , update : msg -> model -> model
    , encodeMsg : msg -> Value
    , decoderMsg : Decoder msg
    , encodeModel : model -> Value
    , decoderModel : Decoder model
    }


toWidget : Form a customError -> Widget FormState Msg a customError
toWidget f =
    let
        widgetErrors formState =
            let
                ( data, validator ) =
                    f.fn.combine formState
            in
            validator data
    in
    
    { init = init
    , value = \formState -> f.fn.combine formState |> Tuple.first
    , validate =
        \formState -> widgetErrors formState
    , view = 
        \domId ((FormState model) as fs) -> 
            f.fn.view (FormState { model | parentDomId = domId }) (widgetErrors fs)
    , update = \(FormMsg fieldId value) model -> updateField f fieldId value model
    , encodeMsg =
        \(FormMsg fieldId value) ->
            E.object [ ( "fieldId", E.int fieldId ), ( "value", value ) ]
    , decoderMsg = D.map2 FormMsg (D.field "fieldId" D.int) (D.field "value" D.value)
    , encodeModel = \(FormState { values }) -> E.dict fromInt identity values
    , decoderModel = formStateDecoder
    }


formStateDecoder : Decoder FormState
formStateDecoder =
    D.dict D.value
        |> D.andThen (\d -> D.succeed <| FormState { values = keysToInt d, parentDomId = "" })


keysToInt : Dict String v -> Dict Int v
keysToInt d =
    Dict.toList d
        |> List.map (\( k, v ) -> ( withDefault -1 (toInt k), v ))
        |> Dict.fromList


type Error customError
    = MustNotBeBlank
    | CustomError customError


type alias Validator a e =
    a -> List (Error e)


alwaysValid : Validator a e
alwaysValid _ =
    []


extract : { form | fn : { b | combine : FormState -> ( data, Validator data customError ) } } -> FormState -> data
extract { fn } =
    Tuple.first << fn.combine


