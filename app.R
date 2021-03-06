library(BTYD)
library(shiny)
library(dplyr)
library(BTYDplus)
library(data.table)
library(ggplot2)
library(tidyr)
library(DT)

cdnow <- fread('cdnow_elog.csv')
cdnow[, date := as.Date(date, '%Y-%m-%d')]
cdnow[, first := min(date), by='cust']


grocery <- fread('grocery-elog.csv')[, first:=NULL]
grocery[, date := as.Date(date, '%Y-%m-%d')]
grocery[, first := min(date), by='cust']



ui <- fluidPage(
    headerPanel('BTYD shiny demo'),
    sidebarPanel(
        selectInput('Data','Select the dataset',choices = c('CDNOW','Grocery')),
        selectInput('Model','Select the model',choices = c('Pareto/NBD', 'BG/NBD', 'MBG/NBD', 'MBG/CNBD-k')),
        sliderInput("cal_per",value = 50,max = 70,min = 30,post = '%',label = "Calibration/holdout split"),
        actionButton(inputId = 'go',label = 'update'),

        width = 3
    ),
    mainPanel(tabsetPanel(
        tabPanel(title = 'Descriptive Summary Statistic',
                 tableOutput('descr_stats'),

                 h4('Plot Of Timing Patterns'),
                 plotOutput('tim_pat'),
                 h6('Copyright(c) 2017 Daniil Yefimov,Michael Platzer, Institut fuer Marketing und Tourismus')
                 ),
        tabPanel(title = 'Cohort Level Analysis',
                 h4('Estimated Parameters '),
                 tableOutput('est_param'),

                 h4('Tracking Incremental & Cumulative Weekly'),
                 plotOutput('incr_weekly'),
                 plotOutput('cum_weekly'),

                 h4('distribution of P(alive)'),
                 plotOutput('p_alive'),

                 h4('Frequency and Recency vs Holdout Transactions'),
                 plotOutput('freq_trans'),
                 plotOutput('rec_trans')),





        tabPanel(title = 'Customer Level Analysis',
                 h4('Sufficient Statistic Matrix'),
                 dataTableOutput('suf_mat'),
                 h6('*cust - customer id (unique key)'),
                 h6('*x - Number of recurring events in calibration period.'),
                 h6('*t.x - Time between first and last event in calibration period.'),
                 h6('*litt - Sum of logarithmic intertransaction timings during calibration period.'),
                 h6('*sales - Sum of sales in calibration period. Only if elog$sales is provided.'),
                 h6('*T.cal - Time between first event and end of calibration period.'),
                 h6('*T.star - Length of holdout period. Only if T.cal is provided.'),
                 h6('*x.star - Number of events within holdout period. Only if T.cal is provided.'),
                 h6('*sales.star - Sum of sales within holdout period. Only if T.cal and elog$sales are provided.'),
                 h6('*xstar.model - Conditional expected transactions'),
                 h6('*palive - Probability of alive')
        )
    )
    )
    
)

server <- function(input,output){
    data_elog <- eventReactive(input$go,{
        data <- list(CDNOW = cdnow, Grocery = grocery)
        data$selected <- data[[input$Data]]
        data
    })

    data_cbs <- eventReactive(input$go,{
        cbs_cdnow <- elog2cbs(cdnow, units = 'week', T.cal = sort(unique(cdnow$date))[uniqueN(cdnow$date)*input$cal_per/100])


        cbs_grocery <- elog2cbs(grocery, T.cal = sort(unique(grocery$date))[uniqueN(grocery$date)*input$cal_per/100])

        #Take the length of the unique dates in dataset and * on the number from 0.25 till 0.75 => new date for calibration period.

        data <- list(CDNOW = cbs_cdnow, Grocery = cbs_grocery)
        data$selected <- data[[input$Data]]

        data
    })

    model <- eventReactive(input$go,{
      data <- data_cbs()$selected
      if(input$Model == "Pareto/NBD"){
        params.pnbd <- BTYD::pnbd.EstimateParameters(data,max.param.value = 100)
        palive.pnbd <- BTYD::pnbd.PAlive(params = params.pnbd, data$x, data$t.x, data$T.cal)
        plot_freq_trans_fn <- pnbd.PlotFreqVsConditionalExpectedFrequency
        incr_weekly <- pnbd.PlotTrackingInc
        cum_weekly <- pnbd.PlotTrackingCum
        rec_trans <- pnbd.PlotRecVsConditionalExpectedFrequency
        
        est_param <- rbind(params.pnbd)
        colnames(est_param) <- c("r", "alpha", "s", "beta")
        
        suf_mat <- data
        suf_mat$palive.pnbd <- round(palive.pnbd,2)
        suf_mat$xstar.model <- round(BTYD::pnbd.ConditionalExpectedTransactions(
          params  = params.pnbd,
          T.star  = suf_mat$T.star,
          x       = suf_mat$x,
          t.x     = suf_mat$t.x,
          T.cal   = suf_mat$T.cal),2)
        suf_mat <- arrange(suf_mat,desc(xstar.model))
        rows_middle <- (nrow(suf_mat)/2) + 5
        suf_mat <- as.data.frame(rbind(head(suf_mat),suf_mat[(nrow(suf_mat)/2):rows_middle,],tail(suf_mat)))
        bool.numeric <- sapply(suf_mat, is.numeric)
        suf_mat <- sapply(suf_mat[bool.numeric], round,2)
        
        l <- list(params = params.pnbd,palive = palive.pnbd,plot_freq = plot_freq_trans_fn,incr_weekly = incr_weekly,cum_weekly = cum_weekly,rec_trans = rec_trans,est_param = est_param,suf_mat = suf_mat)
      }else if(input$Model == "BG/NBD"){
        params.bgnbd <- BTYD::bgnbd.EstimateParameters(data)
        palive.bgnbd <- BTYD::bgnbd.PAlive(params = params.bgnbd, data$x, data$t.x, data$T.cal)
        plot_freq_trans_fn <- bgnbd.PlotFreqVsConditionalExpectedFrequency
        incr_weekly <- bgnbd.PlotTrackingInc
        cum_weekly <-  bgnbd.PlotTrackingCum
        rec_trans <-  bgnbd.PlotRecVsConditionalExpectedFrequency
        
        est_param <- rbind(params.bgnbd)
        colnames(est_param) <- c("r", "alpha", "a", "b")
        
        suf_mat <- data
        suf_mat$palive.bgnbd <- round(palive.bgnbd,2)
        suf_mat$xstar.model <-  round(BTYD::bgnbd.ConditionalExpectedTransactions(
          params  = params.bgnbd,
          T.star  = suf_mat$T.star,
          x       = suf_mat$x,
          t.x     = suf_mat$t.x,
          T.cal   = suf_mat$T.cal),2)
        suf_mat <- arrange(suf_mat,desc(xstar.model))
        rows_middle <- (nrow(suf_mat)/2) + 5
        suf_mat <- as.data.frame(rbind(head(suf_mat),suf_mat[(nrow(suf_mat)/2):rows_middle,],tail(suf_mat)))
        bool.numeric <- sapply(suf_mat, is.numeric)
        suf_mat <- sapply(suf_mat[bool.numeric], round,2)
        
        l <- list(params = params.bgnbd,palive = palive.bgnbd,plot_freq = plot_freq_trans_fn,incr_weekly = incr_weekly,cum_weekly = cum_weekly,rec_trans = rec_trans,est_param = est_param,suf_mat = suf_mat)
      }else if(input$Model == "MBG/NBD"){
        params.mbgnbd <- mbgnbd.EstimateParameters(data)
        palive.mbgnbd <- mbgcnbd.PAlive(params = params.mbgnbd, data$x, data$t.x, data$T.cal)
        incr_weekly <- mbgcnbd.PlotTrackingInc
        cum_weekly <- mbgcnbd.PlotTrackingCum
        
        rec_trans <- bgcnbd.PlotRecVsConditionalExpectedFrequency
        plot_freq_trans_fn <- bgcnbd.PlotFreqVsConditionalExpectedFrequency
        
        est_param <- rbind(params.mbgnbd)
        colnames(est_param) <- c("k","r", "alpha", "a", "b")
        
        suf_mat <- data
        suf_mat$palive.mbgnbd <- round(palive.mbgnbd,2)
        suf_mat$xstar.model <- round(mbgcnbd.ConditionalExpectedTransactions(
          params  = params.mbgnbd,
          T.star  = suf_mat$T.star,
          x       = suf_mat$x,
          t.x     = suf_mat$t.x,
          T.cal   = suf_mat$T.cal),2)
        suf_mat <- arrange(suf_mat,desc(xstar.model))
        rows_middle <- (nrow(suf_mat)/2) + 5
        suf_mat <- as.data.frame(rbind(head(suf_mat),suf_mat[(nrow(suf_mat)/2):rows_middle,],tail(suf_mat)))
        bool.numeric <- sapply(suf_mat, is.numeric)
        suf_mat <- sapply(suf_mat[bool.numeric], round,2)
        
        l <- list(params = params.mbgnbd,palive = palive.mbgnbd,incr_weekly = incr_weekly,cum_weekly = cum_weekly,est_param = est_param,suf_mat = suf_mat,rec_trans = rec_trans,plot_freq= plot_freq_trans_fn)
      }else if(input$Model == "MBG/CNBD-k"){
        params.mbgcnbd <- mbgcnbd.EstimateParameters(data)
        palive.mbgcnbd <- mbgcnbd.PAlive(params = params.mbgcnbd, data$x, data$t.x, data$T.cal)
        incr_weekly <- mbgcnbd.PlotTrackingInc
        cum_weekly <- mbgcnbd.PlotTrackingCum
        
        est_param <- rbind(params.mbgcnbd)
        colnames(est_param) <- c("k","r", "alpha", "a", "b")
        
        rec_trans <- bgcnbd.PlotRecVsConditionalExpectedFrequency
        plot_freq_trans_fn <- bgcnbd.PlotFreqVsConditionalExpectedFrequency
        
        suf_mat <- data
        suf_mat$palive.mbgcnbd <- round(palive.mbgcnbd,2)
        suf_mat$xstar.model <- round(mbgcnbd.ConditionalExpectedTransactions(
          params  = params.mbgcnbd,
          T.star  = suf_mat$T.star,
          x       = suf_mat$x,
          t.x     = suf_mat$t.x,
          T.cal   = suf_mat$T.cal),2)
        suf_mat <- arrange(suf_mat,desc(xstar.model))
        rows_middle <- (nrow(suf_mat)/2) + 5
        suf_mat <- as.data.frame(rbind(head(suf_mat),suf_mat[(nrow(suf_mat)/2):rows_middle,],tail(suf_mat)))
        bool.numeric <- sapply(suf_mat, is.numeric)
        suf_mat <- sapply(suf_mat[bool.numeric], round,2)
        
        l <- list(params = params.mbgcnbd,palive = palive.mbgcnbd,incr_weekly = incr_weekly,cum_weekly = cum_weekly,est_param = est_param,suf_mat = suf_mat,rec_trans = rec_trans,plot_freq= plot_freq_trans_fn)
      }
      
    })

    output$descr_stats <- renderTable({
        cbs_cdnow <- data_cbs()$CDNOW
        cbs_grocery <- data_cbs()$Grocery
        #a)dataset
        dataset <- c("CDs","Grocery")
        #b)Cohort size
        coh.size <- c(nrow(cbs_cdnow),nrow(cbs_grocery))
        #c)Period length in weeks(Calibration)
        per.length.cal <- c(round(max(cbs_cdnow$T.cal)),round(max(cbs_grocery$T.cal)))
        #d)Period length in weeks(holdout)
        per.length.hold <- c(round(cbs_cdnow$T.star[1]),round(cbs_grocery$T.star[1]))
        #e)share of inactive customer(calibr)
        sh.in.cust.cal <- c(round(sum(cbs_cdnow$x == 0)/nrow(cbs_cdnow),2),round(sum(cbs_grocery$x == 0)/nrow(cbs_grocery),2))*100
        #f)share of inactive customer(holdout)
        sh.in.cust.hold <- c(round(sum(cbs_cdnow$x.star == 0)/nrow(cbs_cdnow),2),round(sum(cbs_grocery$x.star == 0)/nrow(cbs_grocery),2))*100
        #g)share of customers with 4 or > transactions(calibration)
        sh.cust.4.plus.cal <- c(round((sum(cbs_cdnow$x >=4)/nrow(cbs_cdnow)),2),round(sum((cbs_grocery$x >=4)/nrow(cbs_grocery)),2))*100
        #h)share of customers with 4 or > transactions(holdout)
        sh.cust.4.plus.hold <- c(round((sum(cbs_cdnow$x.star >=4)/nrow(cbs_cdnow)),2),round(sum((cbs_grocery$x.star >=4)/nrow(cbs_grocery)),2))*100
        #i)mean 0f number of purchases(calibr)
        num.purch.cal <- c(round(mean(cbs_cdnow$x),2),round(mean(cbs_grocery$x),2))
        #j)mean 0f number of purchases(holdout)
        num.purch.hold <- c(round(mean(cbs_cdnow$x.star),2),round(mean(cbs_grocery$x.star),2))
        #k)mean 0f number of purchases active cust(calibr)
        num.purch.cal.act <- c(round(mean(cbs_cdnow$x[cbs_cdnow$x>0]),2),round(mean(cbs_grocery$x[cbs_grocery$x>0]),2))
        #l)mean 0f number of purchases active cust(hold)
        num.purch.hold.act <- c(round(mean(cbs_cdnow$x.star[cbs_cdnow$x.star>0]),2))
        #m)wheat
        wheat <- c(round(estimateRegularity(cdnow, method = "wheat",plot = FALSE),2),round(estimateRegularity(grocery, method = "wheat",plot = FALSE),2))
        #Table:
        des_stat <- c()
        des_stat<- cbind(des_stat ,dataset,coh.size,per.length.cal,per.length.hold,sh.in.cust.cal,sh.in.cust.hold,
                         sh.cust.4.plus.cal,sh.cust.4.plus.hold,num.purch.cal,num.purch.hold,
                         num.purch.cal.act,num.purch.hold.act,wheat)
        des_stat <- as.data.frame(des_stat)
        des_stat[,5:8] <- lapply(des_stat[,5:8],function(x){paste(x,'%',sep = "")})
        des_stat <- data.frame(lapply(des_stat, as.character), stringsAsFactors=FALSE)
        d <- cbind(des_stat[1:2], do.call(cbind, lapply(c(3,5,7,9,11), function(i) do.call(paste, c(des_stat[i:(i+1)], sep="/")))))
        d <- cbind(d,wheat)
        d <- as.data.frame(d)

        colnames(d) <- c("Dataset","Cohort size","Period length (Calibration/Holdout)","Share of inactive customer(cal/hol)",
                         "Share of customers with 4 or > transactions(cal/hol)","Mean of № of purchases(cal/hol)",
                         "Mean of № of purchases active cust(cal/hol)",'wheat')
        d
    })



    output$tim_pat <- renderPlot({
        data <- data_elog()$selected
        plotTimingPatterns(data, n = 30, T.cal = sort(unique(data$date))[uniqueN(data$date)*input$cal_per/100],
                           headers = c("Calibration Period", "Holdout Period"), title = "")
    })



    output$p_alive <- renderPlot({
        plot <- ggplot(as.data.frame(model()$palive),aes(x=model()$palive))+
            geom_histogram(binwidth =0.01,colour="black",fill="orange")+
            ylab("Number of Customers")+
            xlab("Probability Customer is 'Live'")+
            theme_minimal()
        plot
        })

    output$freq_trans <-renderPlot({
        data <- data_cbs()$selected
        param <- model()$params
        k <- model()$plot_freq(param,data$T.star[1],data ,data$x.star,censor =7)


        })


    output$incr_weekly <-renderPlot({
        data <- data_elog()$selected
        data_cbs <- data_cbs()$selected
        param <-model()$params
        model()$incr_weekly(param,round(data_cbs$T.cal),T.tot = max(data_cbs$T.cal + data_cbs$T.star),actual.inc.tracking.data =elog2inc(data))
        })

    output$cum_weekly <- renderPlot({
        data <- data_elog()$selected
        data_cbs <- data_cbs()$selected
        param <-model()$params
        model()$cum_weekly(param,round(data_cbs$T.cal),T.tot = max(data_cbs$T.cal + data_cbs$T.star),actual.cu.tracking.data =elog2cum(data))
        })

    output$est_param <- renderTable({
        est_param<-model()$est_param
        })

    output$rec_trans <-renderPlot({
        data_cbs <- data_cbs()$selected
        param <-model()$params
        k <-model()$rec_trans(param,data_cbs,data_cbs$T.star[1],data_cbs$x.star)

        })
    ##no sales data in Donations and Grocery
    output$suf_mat <- renderDataTable({
      
      datatable(model()$suf_mat,options = list(
        pageLength = 25,
        rowCallback = JS('function(row, data, index, rowId) {',
                         'console.log(rowId)',
                         'if(rowId < 6) {',
                         'row.style.backgroundColor = "green";',
                         '}',
                         'if(rowId >= ', nrow(model()$suf_mat) - 6,') {',
                         'row.style.backgroundColor = "red";',
                         '}',
                         '}')
      )
      )
    })
    
}

shinyApp(ui = ui, server = server)
